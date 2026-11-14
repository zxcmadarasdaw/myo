.pragma library
.import "AudioStream.js" as AudioStream

function updateGraph(graph, batch) {
    for (const object of batch) {
        if (object.info === null || object.props === null) {
            graph.delete(object.id);
        } else if (object.info && (object.type === "PipeWire:Interface:Node"
                   || object.type === "PipeWire:Interface:Client" || object.type === "PipeWire:Interface:Link")) {
            graph.set(object.id, object);
        }
    }
}

function isTrue(value) {
    return value === true || value === "true";
}

function belongsToShell(properties, client, shellPid) {
    return AudioStream.isSerpantinumStream(properties) || AudioStream.isSerpantinumStream(client)
        || (shellPid > 0 && [properties["application.process.id"], properties["pipewire.sec.pid"],
                             client["application.process.id"], client["pipewire.sec.pid"]]
                .some(pid => Number(pid) === shellPid));
}

function isAudible(info) {
    return !(info.params?.Props || []).some(p => isTrue(p.mute) || p.volume === 0
        || (p.channelVolumes?.length > 0 && p.channelVolumes.every(volume => volume === 0)));
}

function activity(graph, shellPid) {
    const outputs = new Set();
    const microphoneInputs = new Set();
    for (const object of graph.values()) {
        if (object.type !== "PipeWire:Interface:Link" || object.info.state !== "active") continue;
        const from = Number(object.info["output-node-id"]);
        const to = Number(object.info["input-node-id"]);
        outputs.add(from);
        const source = graph.get(from)?.info.props || {};
        const mediaClass = String(source["media.class"] || "");
        if ((mediaClass === "Audio/Source" || mediaClass.startsWith("Audio/Source/"))
            && source["device.class"] !== "monitor" && !String(source["node.name"] || "").endsWith(".monitor")) {
            microphoneInputs.add(to);
        }
    }

    let playback = false;
    let calls = false;
    for (const node of graph.values()) {
        if (node.type !== "PipeWire:Interface:Node" || node.info.state !== "running") continue;
        const props = node.info.props || {};
        const client = graph.get(Number(props["client.id"]))?.info.props || {};
        if (isTrue(props["pulse.corked"]) || belongsToShell(props, client, shellPid)) continue;

        if (props["media.class"] === "Stream/Input/Audio" && microphoneInputs.has(node.id)
            && !isTrue(props["stream.monitor"]) && !isTrue(props["stream.capture.sink"])) {
            calls = true;
        }
        if (props["media.class"] !== "Stream/Output/Audio" || !outputs.has(node.id)) continue;
        const role = String(props["media.role"] || "").toLowerCase();
        if (role === "communication" || role === "phone" || role === "voip") {
            calls = true;
        } else if (isAudible(node.info)) {
            playback = true;
        }
    }
    return { playback: playback, calls: calls };
}
