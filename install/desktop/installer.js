"use strict";

const $ = (id) => document.getElementById(id);
const key = location.hash.slice(1);
if (key) {
  sessionStorage.setItem("serpantinum-installer", key);
  history.replaceState(null, "", "/");
}
const session = key || sessionStorage.getItem("serpantinum-installer") || "";
let cursor = 0;
let manual = false;
let running = false;
let closed = false;
let lastPrompt = "";
let shownLog = "";
let generation = 0;
let approval = null;

function element(tag, label, className) {
  const node = document.createElement(tag);
  if (label) node.textContent = label;
  if (className) node.className = className;
  return node;
}

async function request(url, data) {
  const headers = { "X-Installer-Key": session };
  const options = { headers, cache: "no-store" };
  if (data !== undefined) {
    options.method = "POST";
    options.body = JSON.stringify(data);
    headers["Content-Type"] = "application/json";
  }
  const response = await fetch(url, options);
  if (!response.ok) throw new Error((await response.json()).error);
  return response.headers.get("Content-Type").startsWith("text/plain") ? response.text() : response.json();
}

function showError(error) {
  $("error").textContent = error ? error.message : "";
  $("error").hidden = !error;
}

function list(target, entries) {
  target.replaceChildren(...entries.map(([entry]) => element("li", entry)));
  target.hidden = entries.length === 0;
}

function choice(kind, name, value, label, checked = false) {
  const control = element("input");
  Object.assign(control, { type: kind, name, value, checked });
  const field = element("label");
  field.append(control, element("span", label));
  return field;
}

function renderInventory(records) {
  const [os, distribution, pm, version, commit, state] = records.meta[0];
  $("os").textContent = os || distribution;
  $("manager").textContent = pm;
  $("version").textContent = commit === "unknown" ? version : `${version} · ${commit}`;
  $("existing").textContent = { current: "Detected", legacy: "Legacy install", fresh: "New setup" }[state] || state;
  list($("warnings"), [...(records.warning || []), ...(records.error || [])]);
  const entries = (records.component || []).map(([name, status, detail]) => {
    const item = element("details", "", "component");
    const heading = element("summary");
    const badge = element("span", status, "badge");
    badge.dataset.state = status;
    heading.append(element("strong", name), badge);
    item.append(heading, element("p", detail));
    return item;
  });
  $("components").replaceChildren(...entries);
  renderPackages(records.package || []);
  $("free-space").replaceChildren(...diskRows(records.disk || []));
}

function renderPackages(packages) {
  const installed = packages.filter((row) => row[1] === "Installed").length;
  $("package-count").textContent = `${installed} installed · ${packages.length - installed} missing or outdated`;
  const entries = packages.map(([name, status]) =>
    element("div", `${name} · ${status}`, status === "Installed" ? "package" : "package missing"));
  $("packages").replaceChildren(...entries);
}

function openPreparation(state) {
  renderInventory(state.inventory);
  const selected = state.inventory.selected[0][0].split(" ");
  if (!selected[0]) selected[0] = "hyprland";
  const maintenance = state.inventory.meta[0][5] === "current";
  const initial = maintenance ? "verify" : "install";
  for (const [value, label] of Object.entries(state.actions)) {
    $("actions").append(choice("radio", "action", value, label, value === initial));
  }
  for (const name of state.compositors) {
    const label = { hyprland: "Hyprland", sway: "Sway", niri: "Niri", mango: "MangoWC" }[name];
    $("compositors").append(choice("checkbox", "compositor", name, label, selected.includes(name)));
  }
  for (const [value, label] of Object.entries(state.options)) {
    if (["sync", "aur"].includes(value) && state.inventory.meta[0][2] !== "pacman") continue;
    $("options").append(choice("checkbox", "option", value, label, ["config", "backup"].includes(value)));
  }
  changeSelection();
}

function selection() {
  const checked = (name) => Array.from(document.querySelectorAll(`input[name="${name}"]:checked`), (node) => node.value);
  return { action: checked("action")[0], compositors: checked("compositor"), options: checked("option") };
}

function changeSelection() {
  generation++;
  approval = null;
  $("plan").hidden = true;
  $("start").disabled = true;
  const value = selection().action === "verify";
  $("settings").hidden = value;
}

function mib(kib) {
  return /^\d+$/.test(kib) ? `${(Number(kib) / 1024).toFixed(1)} MiB` : kib;
}

function diskRows(disks) {
  return disks.map(([path, needed, free]) =>
    element("div", `${path} · ${mib(needed)} preflight minimum · ${mib(free)} free`));
}

async function review() {
  const revision = generation;
  const data = selection();
  const records = await request("/review", data);
  if (revision !== generation) return;
  approval = records.approval;
  renderPackages(records.package || []);
  const changes = records.change || (data.action === "verify" ? [["Check installed files and dependencies."]] : []);
  list($("changes"), changes);
  list($("plan-errors"), [...(records.warning || []), ...(records.error || [])]);
  $("space").replaceChildren(...diskRows(records.disk || []));
  const packages = (records.package || []).filter((row) => row[1] !== "Installed").map((row) => row[0]);
  $("target-packages").hidden = packages.length === 0;
  $("targets").textContent = packages.join(", ");
  $("plan-heading").textContent = data.action === "verify" ? "Review verification" : "Review changes";
  $("start").textContent = data.action === "verify" ? "Run verification" : "Approve and start";
  $("start").disabled = Boolean(records.error?.length);
  $("plan").hidden = false;
  $("plan").scrollIntoView({ block: "nearest" });
}

function flags(inProgress) {
  running = inProgress;
  for (const id of ["review", "refresh", "close", "compositors", "options"]) $(id).disabled = running;
  for (const input of $("actions").querySelectorAll("input")) input.disabled = running;
}

async function start(route) {
  if (running) return;
  flags(true);
  $("start").disabled = true;
  try {
    await request(route, route === "/start" ? { approval } : {});
    cursor = 0;
    manual = false;
    lastPrompt = "";
    $("lines").replaceChildren();
    $("answer").value = "";
    $("plan").hidden = true;
    $("operation").hidden = false;
    $("operation").scrollIntoView({ block: "nearest" });
  } catch (error) {
    flags(false);
    $("start").disabled = false;
    throw error;
  }
}

function updateProgress(progress, value, total) {
  if (Number.isFinite(value) && Number.isFinite(total)) {
    progress.max = total;
    progress.value = value;
  } else {
    progress.removeAttribute("value");
  }
}

function renderRun(run, launchError) {
  flags(run.code === null);
  $("operation").hidden = false;
  const ok = run.code === 0 && run.status === "Completed";
  $("status").textContent = ok ? (run.total === 1 ? "VERIFICATION COMPLETED" : "INSTALLATION COMPLETED") : run.status;
  $("status").dataset.state = run.status;
  $("current").textContent = run.phase ? `Phase ${run.phase} of ${run.total} · ${run.component}` : run.component;
  $("elapsed").textContent = `${Math.floor(run.elapsed / 60)}m ${run.elapsed % 60}s`;
  updateProgress($("overall"), run.completed, run.total);
  $("transfer").hidden = run.status !== "Downloading";
  updateProgress($("download"), run.metrics.percent, 100);
  $("metrics").textContent = [run.metrics.package, run.metrics.count, run.metrics.size, run.metrics.rate, run.network].filter(Boolean).join(" · ");
  const activity = run.active < 20 ? "Worker activity detected" : `No observable process activity for ${run.active}s`;
  $("activity").textContent = [running ? `${activity} · last output ${run.idle}s ago` : "", run.latest].filter(Boolean).join(" · ");
  if (running && run.idle >= 20 && run.processes.length) {
    $("activity").textContent += ` · Processes: ${run.processes.join(", ")}`;
  }

  if (shownLog !== run.path) {
    shownLog = run.path;
    $("lines").replaceChildren();
    cursor = 0;
  }
  const journal = $("lines");
  const follow = journal.scrollHeight - journal.clientHeight - journal.scrollTop < 36;
  for (const [idx, line] of run.lines) {
    cursor = Math.max(cursor, idx);
    journal.append(document.createTextNode(line + "\n"));
  }
  while (journal.childNodes.length > 800) journal.firstChild.remove();
  if (follow) journal.scrollTop = journal.scrollHeight;
  $("log-path").textContent = run.path;

  const asking = running && run.status !== "Cancelling" && (manual || run.prompt);
  $("question").hidden = !asking;
  $("prompt").textContent = run.prompt || run.partial || "Enter a response to the current terminal request.";
  $("answer").type = run.secret ? "password" : "text";
  if (run.prompt && lastPrompt !== run.prompt) {
    $("journal").open = true;
    journal.scrollTop = journal.scrollHeight;
  }
  lastPrompt = run.prompt;
  $("manual").hidden = !running || run.status === "Cancelling";
  $("cancel").hidden = !running;
  $("cancel").disabled = run.status === "Cancelling";
  $("retry").hidden = running || ok;
  $("restart").hidden = running || ok;
  $("launch").hidden = !ok;
  $("recovery").hidden = !launchError && (running || ok);
  $("recovery").textContent = launchError || run.diagnostic ||
    "Review the last operation and journal. After resolving the cause, retry the failed step or restart the approved plan.";
}

async function poll() {
  if (closed) return;
  try {
    const state = await request(`/status?${cursor}`);
    if (state.run) renderRun(state.run, state.launchError);
  } catch (error) {
    showError(error);
  }
  setTimeout(poll, 450);
}

function click(id, handler) {
  $(id).addEventListener("click", async () => {
    showError(null);
    try { await handler(); }
    catch (error) { showError(error); }
  });
}

async function answer() {
  const value = $("answer").value;
  const secret = $("answer").type === "password";
  $("answer").value = "";
  await request("/answer", { answer: value, secret });
  manual = false;
  $("question").hidden = true;
}

click("review", review);
click("start", () => start("/start"));
click("retry", () => start("/retry"));
click("restart", () => start("/restart"));
click("cancel", () => request("/cancel", {}));
click("send", answer);
click("manual", () => {
  manual = true;
  $("journal").open = true;
  $("question").hidden = false;
  $("answer").focus();
});
click("launch", () => request("/launch", {}));
click("refresh", async () => {
  const inventory = await request("/refresh", {});
  changeSelection();
  renderInventory(inventory);
});
click("download-log", async () => {
  const journal = await request("/journal");
  const url = URL.createObjectURL(new Blob([journal], { type: "text/plain" }));
  const link = element("a");
  link.href = url;
  link.download = "serpantinum-install.log";
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});
click("close", async () => {
  await request("/close", {});
  closed = true;
  sessionStorage.removeItem("serpantinum-installer");
  document.querySelector("main").replaceChildren(element("h1", "Installer closed"));
});
$("preparation").addEventListener("change", changeSelection);
$("answer").addEventListener("keydown", (event) => {
  if (event.key === "Enter") $("send").click();
});
request("/inventory")
  .then((state) => { openPreparation(state); poll(); })
  .catch(showError);
