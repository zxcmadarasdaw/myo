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
let lastQueueEnd = "";
let savedPlan = null;
let installerInventory;

const installerRussian = new Map(Object.entries({
  "Installation manager": "Менеджер установки",
  "Close installer": "Закрыть установщик",
  "Installer closed": "Установщик закрыт",
  "Version": "Версия",
  "Operating system": "Операционная система",
  "Package manager": "Пакетный менеджер",
  "Installation": "Установка",
  "Loading": "Загрузка",
  "Components": "Компоненты",
  "Refresh": "Обновить данные",
  "Package inventory": "Список пакетов",
  "Disk space": "Место на диске",
  "Prepare installation": "Подготовка установки",
  "Desktop sessions": "Сеансы рабочего стола",
  "Configuration and optional components": "Конфигурация и дополнительные компоненты",
  "Package download mode": "Режим загрузки пакетов",
  "Review changes": "Просмотреть изменения",
  "Review verification": "Просмотреть план проверки",
  "Review saved plan": "Просмотреть сохранённый план",
  "Run verification": "Запустить проверку",
  "Packages missing or due for update": "Отсутствующие или устаревшие пакеты",
  "Approve and start": "Подтвердить и запустить",
  "Installation progress": "Ход установки",
  "Installation phases": "Этапы установки",
  "Current transfer": "Текущая загрузка",
  "Package downloads": "Загрузка пакетов",
  "Native package manager": "Штатный пакетный менеджер",
  "Parallel downloads": "Параллельные загрузки",
  "Packages in transaction": "Пакеты в транзакции",
  "Native cache": "Системный кэш",
  "Package verification failed": "Ошибка проверки пакетов",
  "Package download failed": "Ошибка загрузки пакетов",
  "Native transaction failed": "Ошибка транзакции пакетного менеджера",
  "Native transaction complete": "Транзакция пакетного менеджера завершена",
  "Native transaction completed with warnings": "Транзакция пакетного менеджера завершена с предупреждениями",
  "Advanced options": "Расширенные параметры",
  "Live Test Mode": "Режим проверки Live",
  "Install optional capture, OCR and desktop utilities": "Установить дополнительные утилиты для записи, OCR и рабочего стола",
  "Download report": "Отчёт о загрузке",
  "Retry Failed Downloads": "Повторить неудачные загрузки",
  "Export Installation Report": "Сохранить отчёт об установке",
  "Send response": "Отправить ответ",
  "Read the transaction in the journal before answering. An empty response uses the command’s default.": "Прочитайте сведения о транзакции в журнале. Пустой ответ выбирает действие по умолчанию.",
  "Respond to a terminal prompt": "Ответить на запрос терминала",
  "Cancel safely": "Отменить",
  "Retry failed step": "Повторить неудачный шаг",
  "Restart approved plan": "Перезапустить подтверждённый план",
  "Launch Serpantinum": "Запустить Serpantinum",
  "Installation journal": "Журнал установки",
  "Save full journal": "Сохранить полный журнал",
  "Install": "Установить",
  "Verify": "Проверить",
  "Repair": "Восстановить",
  "Update": "Обновить Serpantinum",
  "Install Missing": "Установить недостающее",
  "Deploy compositor and Kitty configuration": "Развернуть конфигурацию композитора и Kitty",
  "Replace matching config files with mandatory backups": "Заменить совпадающие файлы конфигурации с резервным копированием",
  "Take a private settings snapshot first": "Сначала создать локальную копию настроек",
  "Install compatibility launch links in /usr/local/bin": "Установить ссылки для совместимости в /usr/local/bin",
  "Configure system and PipeWire services (includes PAM)": "Настроить системные службы, PipeWire и PAM",
  "Install and configure SDDM and its theme": "Установить и настроить SDDM и тему",
  "Use the SDDM Wayland greeter": "Использовать экран входа SDDM на Wayland",
  "Switch the current display manager to SDDM": "Переключить дисплейный менеджер на SDDM",
  "Install Ski, Audio DSP, Core and Gamma": "Установить Ski, Audio DSP, Core и Gamma",
  "Install offline VPN and system TUN integration": "Установить офлайн-VPN и интеграцию TUN",
  "Download Iosevka Nerd Fonts": "Скачать Iosevka Nerd Fonts",
  "Download a small wallpaper selection": "Скачать небольшую подборку обоев",
  "Download the full wallpaper collection": "Скачать полную коллекцию обоев",
  "Refresh pacman databases and upgrade all system packages": "Обновить базы pacman и все системные пакеты",
  "Allow reviewed AUR builds for Quickshell or Umbriel": "Разрешить проверенные сборки Quickshell или Umbriel из AUR",
  "Allow source builds and their build dependencies": "Разрешить сборку из исходников и установку её зависимостей",
  "Send anonymous installation telemetry": "Отправлять анонимную телеметрию установки",
  "Start Serpantinum after verification": "Запустить Serpantinum после проверки",
  "Installed": "Установлено",
  "Missing": "Отсутствует",
  "Optional": "Необязательный компонент",
  "Failed": "Ошибка",
  "Update available": "Доступно обновление",
  "Update required": "Требуется обновление",
  "Detected": "Обнаружена",
  "Legacy install": "Устаревшая установка",
  "New setup": "Новая установка",
  "VERIFICATION COMPLETED": "ПРОВЕРКА ЗАВЕРШЕНА",
  "INSTALLATION COMPLETED": "УСТАНОВКА ЗАВЕРШЕНА",
  "INSTALLATION COMPLETED WITH WARNINGS": "УСТАНОВКА ЗАВЕРШЕНА С ПРЕДУПРЕЖДЕНИЯМИ"
}));
const installerText = (text) => document.documentElement.lang === "ru" ? installerRussian.get(text) || text : text;

function localizeInstaller() {
  const walker = document.createTreeWalker(document.querySelector("main"), NodeFilter.SHOW_TEXT, {
    acceptNode(node) {
      return node.parentElement.closest("#system-updates")
        ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
    }
  });
  const sources = new Map(Array.from(installerRussian, ([english, russian]) => [russian, english]));
  while (walker.nextNode()) {
    const node = walker.currentNode;
    const original = node.data.trim();
    const english = sources.get(original) || original;
    if (installerRussian.has(english)) node.data = node.data.replace(original, installerText(english));
  }
  if (installerInventory) renderInventory(installerInventory);
}

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
  installerInventory = records;
  const [os, distribution, pm, version, commit, state] = records.meta[0];
  $("os").textContent = os || distribution;
  $("manager").textContent = pm;
  $("version").textContent = commit === "unknown" ? version : `${version} · ${commit}`;
  $("existing").dataset.installState = state;
  $("existing").textContent = installerText(records.session?.[0]?.[0] === "live" ? "Live Test Mode"
    : { current: "Detected", legacy: "Legacy install", fresh: "New setup" }[state] || state);
  list($("warnings"), [...(records.warning || []), ...(records.error || [])]);
  const entries = (records.component || []).map(([name, status, detail]) => {
    const item = element("details", "", "component");
    const heading = element("summary");
    const badge = element("span", installerText(status), "badge");
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
  savedPlan = state.saved?.plan;
  $("review-saved").hidden = !savedPlan;
  const selected = state.inventory.selected[0][0].split(" ");
  if (!selected[0]) selected[0] = "hyprland";
  const maintenance = state.inventory.meta[0][5] === "current";
  const initial = maintenance ? "verify" : "install";
  for (const [value, label] of Object.entries(state.actions)) {
    $("actions").append(choice("radio", "action", value, installerText(label), value === initial));
  }
  for (const name of state.compositors) {
    const label = { hyprland: "Hyprland", sway: "Sway", niri: "Niri", mango: "MangoWC", umbriel: "Umbriel" }[name];
    $("compositors").append(choice("checkbox", "compositor", name, label, selected.includes(name)));
  }
  for (const [value, label] of Object.entries(state.options)) {
    if (["sync", "aur"].includes(value) && state.inventory.meta[0][2] !== "pacman") continue;
    $("options").append(choice("checkbox", "option", value, installerText(label), ["config", "backup"].includes(value)));
  }
  changeSelection();
}

function selection() {
  const checked = (name) => Array.from(document.querySelectorAll(`input[name="${name}"]:checked`), (node) => node.value);
  return { action: checked("action")[0], compositors: checked("compositor"), options: checked("option"), download_mode: $("download-mode").value };
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

async function review(saved = false) {
  const revision = generation;
  const data = selection();
  const records = await request(saved ? "/review-saved" : "/review", data);
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
  $("plan-heading").textContent = installerText(data.action === "verify" ? "Review verification" : "Review changes");
  $("start").textContent = installerText(data.action === "verify" ? "Run verification" : "Approve and start");
  $("start").disabled = Boolean(records.error?.length);
  $("plan").hidden = false;
  $("plan").scrollIntoView({ block: "nearest" });
}

function flags(inProgress) {
  running = inProgress;
  for (const id of ["review", "review-saved", "refresh", "close", "compositors", "options", "download-mode"]) $(id).disabled = running;
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
  const nativeErrors = (run.reports || []).flatMap(report => report.native_errors || []);
  const completed = nativeErrors.length ? "INSTALLATION COMPLETED WITH WARNINGS" : "INSTALLATION COMPLETED";
  $("status").textContent = installerText(ok ? (run.total === 1 ? "VERIFICATION COMPLETED" : completed) : run.status);
  $("status").dataset.state = run.status;
  $("current").textContent = run.phase ? `Phase ${run.phase} of ${run.total} · ${run.component}` : run.component;
  $("elapsed").textContent = `${Math.floor(run.elapsed / 60)}m ${run.elapsed % 60}s`;
  updateProgress($("overall"), run.completed, run.total);
  $("transfer").hidden = run.status !== "Downloading";
  updateProgress($("download"), run.metrics.percent, 100);
  $("metrics").textContent = [run.metrics.package, run.metrics.count, run.metrics.size, run.metrics.rate, run.network].filter(Boolean).join(" · ");
  renderQueue(run);
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
  const integration = run.integration && run.integration !== "PENDING"
    ? ["System integration", run.integration, run.integration_detail].filter(Boolean).join(" · ")
    : "";
  const components = Object.entries(run.components || {}).map(([name, info]) => `${name} · ${info.state} · ${info.detail}`);
  $("integration").hidden = !integration && !components.length && !nativeErrors.length;
  $("integration").textContent = [integration, ...components, ...new Set(nativeErrors)].filter(Boolean).join("\n");
  $("recovery").hidden = !launchError && (running || ok);
  $("recovery").textContent = launchError || run.diagnostic ||
    "Review the last operation and journal. After resolving the cause, retry the failed step or restart the approved plan.";
}

function bytes(value) {
  if (!Number.isFinite(value)) return "unknown";
  const unit = value >= 1048576 ? "MiB" : value >= 1024 ? "KiB" : "B";
  const divisor = unit === "MiB" ? 1048576 : unit === "KiB" ? 1024 : 1;
  return `${(value / divisor).toFixed(unit === "B" ? 0 : 1)} ${unit}`;
}

function renderQueue(run) {
  const packages = run.downloads || [];
  $("download-queue").hidden = !run.queue?.stage;
  if (!run.queue?.stage) return;
  const native = run.queue.native;
  for (const id of ["queue-overall", "queue-active", "queue-packages"]) $(id).hidden = !!native;
  if (native) {
    const queue = run.queue;
    $("queue-current").textContent = [queue.backend, installerText("Native package manager"),
      installerText("Parallel downloads") + " " + queue.limit].join(" · ");
    $("queue-counts").textContent = queue.total ? installerText("Packages in transaction") + " " + queue.total : "";
    $("queue-storage").textContent = installerText("Native cache") + " · " + queue.native_cache;
    $("queue-report").hidden = !["INSTALLED", "BLOCKED", "CANCELLED"].includes(queue.stage);
    const label = queue.verification === "FAILED" ? "Package verification failed"
      : queue.download === "FAILED" ? "Package download failed"
      : queue.installation === "SUCCESS_WITH_WARNINGS" ? "Native transaction completed with warnings"
      : queue.installation === "SUCCESS" ? "Native transaction complete"
      : queue.stage === "CANCELLED" ? "Cancelled" : "Native transaction failed";
    $("queue-summary").textContent = [installerText(label), queue.error, ...(queue.native_errors || [])].filter(Boolean).join("\n");
    $("retry-downloads").hidden = running || queue.download !== "FAILED";
    return;
  }
  const good = packages.filter(p => p.checksum_verified ?? ["VERIFIED", "INSTALLED"].includes(p.state)).length;
  const failed = packages.filter(p => p.state === "FAILED").length;
  const deferred = run.queue.deferred ?? packages.filter(p => p.state === "DEFERRED").length;
  const total = run.queue.total ?? packages.length;
  const active = packages.filter(p => p.state === "DOWNLOADING");
  const known = packages.length === total && packages.every(p => Number.isFinite(p.size));
  const totalBytes = known ? packages.reduce((n, p) => n + p.size, 0) : null;
  const received = packages.reduce((n, p) => n + (p.received || 0), 0);
  updateProgress($("queue-overall"), totalBytes ? received : good, totalBytes || total);
  $("queue-counts").textContent = `Completed: ${good} · Failed: ${failed} · Deferred: ${deferred} · Remaining: ${Math.max(0, total - good - (run.queue.deferred !== undefined ? deferred : failed + deferred))} · Total: ${total}`;
  const storage = run.queue.storage;
  $("queue-storage").textContent = storage ? `Cache: ${storage.cache} · Required: ${bytes(storage.cache_required)} · Free: ${bytes(storage.cache_free)}\nTemporary: ${storage.temporary_directory} · Free: ${bytes(storage.temporary_free)}${storage.memory_available ? " · Available RAM: " + bytes(storage.memory_available) : ""}\n${storage.warning || ""}` : "";
  $("queue-current").textContent = run.queue.stage === "DOWNLOAD"
    ? `Active downloads: ${active.length} / ${run.queue.limit ?? 1} · Total speed: ${bytes(run.queue.rate ?? 0)}/s`
    : [run.queue.stage, run.queue.error].filter(Boolean).join(" · ");
  $("transfer").hidden = true;
  $("queue-active").replaceChildren(...active.map(pkg => {
    const row = element("div", "", "queue-active-row");
    const percent = Number.isFinite(pkg.percent) ? ` · ${pkg.percent.toFixed(1)}%` : "";
    const rate = Number.isFinite(pkg.rate) ? ` · ${bytes(pkg.rate)}/s` : "";
    const label = element("div",
      `${pkg.name} ${pkg.version} · ${bytes(pkg.received)} / ${bytes(pkg.size)}${percent}${rate}`);
    const progress = element("progress");
    progress.setAttribute("aria-label", `${pkg.name} download`);
    updateProgress(progress, pkg.percent, 100);
    row.append(label, progress);
    const meta = [pkg.mirror,
      Number.isFinite(pkg.average) ? `Average ${bytes(pkg.average)}/s` : "",
      Number.isFinite(pkg.eta) ? `ETA ${Math.ceil(pkg.eta)}s` : "",
      pkg.warning].filter(Boolean);
    if (meta.length) row.append(element("p", meta.join(" · "), "muted"));
    return row;
  }));
  // Reuse details nodes so expanded rows stay open through progress updates.
  const container = $("queue-packages");
  const names = new Set(packages.map(p => p.name));
  for (const node of [...container.children]) if (!names.has(node.dataset.name)) node.remove();
  const rows = new Map([...container.children].map(node => [node.dataset.name, node]));
  for (const pkg of packages) {
    let row = rows.get(pkg.name);
    if (!row) {
      row = element("details", "", "queue-package");
      row.dataset.name = pkg.name;
      row.append(element("summary"), element("p"));
      container.append(row);
    }
    row.firstChild.textContent = `${pkg.name} · ${pkg.state}${Number.isFinite(pkg.percent) && pkg.state === "DOWNLOADING" ? " · " + pkg.percent.toFixed(1) + "%" : ""}`;
    row.lastChild.textContent = `${pkg.version} · ${pkg.repository} · ${bytes(pkg.received)} / ${bytes(pkg.size)}\nAttempts: ${pkg.attempts} · Mirror: ${pkg.mirror || "pending"}\n${pkg.error || ""} ${pkg.detail || ""}\n${(pkg.history || []).map(h => `${h.attempt}: ${h.reason} · ${h.mirror}`).join("\n")}`;
  }
  const ended = ["DOWNLOAD_COMPLETED", "BLOCKED", "READY", "INSTALLING", "INSTALLED", "CANCELLED"].includes(run.queue.stage) || run.code !== null;
  $("queue-report").hidden = !ended;
  const endKey = `${run.path}:${run.phase}:${run.queue.stage}`;
  if (ended && lastQueueEnd !== endKey) $("queue-report").open = true;
  lastQueueEnd = ended ? endKey : "";
  $("queue-summary").textContent = `Download: ${run.queue.download || "PENDING"}\nVerification: ${run.queue.verification || "PENDING"}\nInstallation: ${run.queue.installation || "PENDING"}\nChecksum verified: ${good} / ${total}\nFailed: ${failed}\n` +
    packages.filter(p => p.error).map(p => `${p.name}: ${p.error} · Attempts: ${p.attempts} · Mirror: ${p.mirror}\n${p.detail || ""}`).join("\n") +
    `\n${[run.queue.error, ...(run.queue.native_errors || [])].filter(Boolean).join("\n")}`;
  $("retry-downloads").hidden = running || run.queue.download !== "FAILED";
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

click("review", () => review());
click("review-saved", () => {
  for (const input of $("preparation").querySelectorAll("input")) {
    input.checked = { action: [savedPlan.action], compositor: savedPlan.compositors, option: savedPlan.options }[input.name].includes(input.value);
  }
  $("download-mode").value = savedPlan.download_mode;
  changeSelection();
  return review(true);
});
click("start", () => start("/start"));
click("retry", () => start("/retry"));
click("retry-downloads", () => start("/retry"));
click("export-report", async () => {
  for (const extension of ["txt", "json"]) {
    const data = await request(`/report.${extension}`);
    const url = URL.createObjectURL(new Blob([extension === "json" ? JSON.stringify(data, null, 2) : data],
      { type: extension === "json" ? "application/json" : "text/plain" }));
    const link = element("a");
    link.href = url;
    link.download = `serpantinum-installation-report.${extension}`;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
});
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
  document.querySelector("main").replaceChildren(element("h1", installerText("Installer closed")));
});
$("preparation").addEventListener("change", changeSelection);
$("answer").addEventListener("keydown", (event) => {
  if (event.key === "Enter") $("send").click();
});
document.addEventListener("DOMContentLoaded", () => {
  request("/inventory")
    .then((state) => {
      openPreparation(state);
      window.dispatchEvent(new CustomEvent("installer-ready", { detail: state }));
      if (!state.updatesOnly) poll();
    })
    .catch(showError);
});
