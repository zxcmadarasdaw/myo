"""Provider interface and Ollama transport. No client credentials leave loopback."""

import http.client
import json
import re
import socket
from contextlib import contextmanager
from typing import Protocol
from urllib.parse import urlsplit


DEFAULT_URL = "http://127.0.0.1:11434"
MAX_RESPONSE = 2 * 1024 * 1024


class ProviderError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.code = code


class AIProvider(Protocol):
    def probe(self, request): ...
    def list_models(self, request): ...
    def chat(self, request, model, messages, options): ...


def local_origin(value):
    if not isinstance(value, str) or not re.fullmatch(
        r"https?://(?:localhost|127\.0\.0\.1|\[::1\])(?::[0-9]{1,5})?/?", value.strip(), re.I
    ):
        raise ProviderError("invalid_url")
    parsed = urlsplit(value.strip())
    try:
        if parsed.port == 0:
            raise ValueError
    except ValueError:
        raise ProviderError("invalid_url") from None
    return parsed.scheme, parsed.hostname, parsed.port


def read_json(data):
    try:
        result = json.loads(data)
    except (ValueError, UnicodeError):
        raise ProviderError("invalid_response") from None
    if not isinstance(result, dict):
        raise ProviderError("invalid_response")
    if "error" in result:
        raise ProviderError("provider_error")
    return result


def normalize_model(item):
    if not isinstance(item, dict):
        raise ProviderError("invalid_response")
    name = item.get("model") or item.get("name")
    if not isinstance(name, str) or not name or len(name) > 512:
        raise ProviderError("invalid_response")
    if item.get("remote_host") or item.get("remote_model") or name.lower().endswith((":cloud", "-cloud")):
        return None
    details = item.get("details")
    details = details if isinstance(details, dict) else {}
    return {
        "id": name,
        "name": name,
        "size": item.get("size") if type(item.get("size")) is int else None,
        **{
            key: details[key][:200]
            for key in ("family", "parameter_size", "quantization_level")
            if isinstance(details.get(key), str)
        },
    }


class OllamaProvider:
    def __init__(self, base_url):
        self.origin = local_origin(base_url)

    @contextmanager
    def response(self, request, path, payload=None):
        scheme, host, port = self.origin
        factory = http.client.HTTPSConnection if scheme == "https" else http.client.HTTPConnection
        # Resolve localhost ourselves so a configured proxy or name service cannot redirect it.
        if host == "localhost":
            host = "127.0.0.1"
        connection = factory(host, port, timeout=min(5, request.timeout))
        response = None
        try:
            connection.connect()
            request.attach_socket(connection.sock)
            connection.sock.settimeout(min(request.idle_timeout, request.timeout))
            if payload is None:
                connection.request("GET", path)
            else:
                connection.request(
                    "POST", path, json.dumps(payload).encode("utf-8"),
                    {"Content-Type": "application/json"},
                )
            response = connection.getresponse()
            if response.status != 200:
                code = {401: "authorization", 403: "authorization", 404: "not_found", 429: "rate_limit"}
                raise ProviderError(code.get(response.status, "provider_error"))
            yield response
        except TimeoutError:
            raise ProviderError("timeout") from None
        except http.client.HTTPException:
            raise ProviderError("invalid_response") from None
        except OSError:
            raise ProviderError("unavailable") from None
        finally:
            if response is not None:
                response.close()
            connection.close()

    def probe(self, request):
        return self.list_models(request)

    def list_models(self, request):
        with self.response(request, "/api/tags") as response:
            raw = response.read(MAX_RESPONSE + 1)
        if len(raw) > MAX_RESPONSE:
            raise ProviderError("invalid_response")
        data = read_json(raw)
        models = data.get("models")
        if not isinstance(models, list):
            raise ProviderError("invalid_response")
        catalog = {}
        for item in models:
            model = normalize_model(item)
            if model:
                catalog[model["id"]] = model
        return list(catalog.values())

    def chat(self, request, model, messages, options):
        stream = options["stream"]
        payload = {
            "model": model, "messages": messages, "stream": stream,
            "options": {"temperature": options["temperature"], "num_predict": options["maxTokens"]},
        }
        with self.response(request, "/api/chat", payload) as response:
            remaining = 4 * MAX_RESPONSE
            while True:
                data = response.readline(MAX_RESPONSE + 1) if stream else response.read(MAX_RESPONSE + 1)
                remaining -= len(data)
                if not data or len(data) > MAX_RESPONSE or remaining < 0:
                    raise ProviderError("invalid_response")
                chunk = read_json(data)
                message = chunk.get("message")
                if not isinstance(message, dict) or not isinstance(message.get("content"), str):
                    raise ProviderError("invalid_response")
                if message["content"]:
                    request.delta(message["content"])
                if chunk.get("done") is True:
                    return {
                        "model": chunk["model"] if isinstance(chunk.get("model"), str) else model,
                        "usage": {
                            key: chunk[key] for key in ("prompt_eval_count", "eval_count")
                            if type(chunk.get(key)) is int
                        },
                    }
                if not stream or chunk.get("done") is not False:
                    raise ProviderError("invalid_response")


class ProviderManager:
    factories = {"ollama": OllamaProvider}

    def resolve(self, profile) -> AIProvider:
        if not isinstance(profile, dict) or not isinstance(profile.get("provider"), str):
            raise ProviderError("invalid_request")
        factory = self.factories.get(profile["provider"])
        if factory is None:
            raise ProviderError("unsupported_provider")
        return factory(profile.get("baseUrl", DEFAULT_URL))
