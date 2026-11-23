"use strict";

const updateLabels = {
  heading: ["System updates", "Обновления системы"],
  checking: ["Checking repositories…", "Проверяем репозитории…"],
  unchecked: ["Check the system for updates", "Проверьте наличие обновлений"],
  available: ["System updates available", "Доступны обновления системы"],
  current: ["System is up to date", "Система обновлена"],
  failedCheck: ["Could not check system updates", "Не удалось проверить обновления системы"],
  check: ["Check for updates", "Проверить обновления"],
  install: ["Download and install", "Скачать и установить"],
  details: ["Details", "Подробнее"],
  history: ["Update history", "История обновлений"],
  mode: ["Package download mode", "Режим загрузки пакетов"],
  packages: ["Transaction packages", "Пакеты в транзакции"],
  count: ["Packages", "Пакеты"],
  download: ["To download", "К загрузке"],
  change: ["Disk change (estimate)", "Изменение на диске (оценка)"],
  repository: ["Repositories", "Репозитории"],
  reachable: ["Metadata loaded", "Метаданные загружены"],
  mirrorErrors: ["Repository and mirror diagnostics", "Диагностика репозиториев и зеркал"],
  mirrorHint: [
    "Check the connection and system clock. If a mirror keeps failing, review the configured mirrors with your distribution’s mirror tool, then check again. Verified archives are reused.",
    "Проверьте соединение и системное время. Если ошибки повторяются, проверьте список зеркал штатной утилитой дистрибутива и повторите проверку. Проверенные архивы используются повторно."
  ],
  diskHint: ["Free space is below the preflight estimate.", "Свободного места меньше, чем требуется по предварительной оценке."],
  space: ["Disk space", "Место на диске"],
  free: ["free", "свободно"],
  needed: ["needed", "требуется"],
  security: ["Security updates", "Обновления безопасности"],
  yes: ["Available", "Доступны"],
  no: ["None reported", "Не обнаружены"],
  rebootFact: ["Reboot", "Перезагрузка"],
  rebootRequired: ["Required", "Требуется"],
  rebootClear: ["Not required", "Не требуется"],
  kernelChanged: ["Recommended · running kernel differs", "Рекомендуется · запущенное ядро отличается"],
  kernelPresent: ["Running kernel is present", "Запущенное ядро есть на диске"],
  unknown: ["Unknown", "Неизвестно"],
  rolling: ["Rolling release", "Непрерывное обновление"],
  live: [
    "Live session. Updates can be checked. Temporary storage is limited and full upgrades are disabled.",
    "Сеанс Live. Проверка доступна. Временное хранилище ограничено, полное обновление отключено."
  ],
  nativePlan: ["Package manager plan", "План пакетного менеджера"],
  additional: ["Additional sources", "Дополнительные источники"],
  noAur: ["AUR updates require an installed paru or yay helper.", "Для обновления AUR нужен установленный paru или yay."],
  aurWait: ["Check and update repository packages before running AUR updates.", "Перед обновлением AUR проверьте и обновите пакеты из репозиториев."],
  aur: ["Update AUR packages", "Обновить пакеты AUR"],
  flatpakUser: ["Update user Flatpaks", "Обновить Flatpak пользователя"],
  flatpakSystem: ["Update system Flatpaks", "Обновить системные Flatpak"],
  progress: ["Update progress", "Ход обновления"],
  journal: ["Package manager journal", "Журнал пакетного менеджера"],
  send: ["Send response", "Отправить ответ"],
  manual: ["Respond to a terminal prompt", "Ответить на запрос терминала"],
  prompt: ["Enter an answer to the current package manager prompt.", "Введите ответ на текущий запрос пакетного менеджера."],
  retry: ["Recheck and retry", "Перепроверить и повторить"],
  export: ["Export update report", "Сохранить отчёт об обновлении"],
  view: ["View journal", "Открыть журнал"],
  noHistory: ["No system update runs recorded by this installer yet.", "Установщик ещё не записал ни одной операции обновления."],
  reboot: ["Reboot now", "Перезагрузить сейчас"],
  desktop: ["Set up Serpantinum Desktop", "Установить Serpantinum Desktop"],
  snapshot: ["Create a Btrfs snapshot with Snapper first", "Сначала создать снимок Btrfs через Snapper"],
  approve: ["Confirm", "Подтвердить"],
  dismiss: ["Back", "Назад"],
  confirmUpgrade: [
    "Approve the reviewed upgrade. Read the final transaction in the package manager journal and answer its prompt.",
    "Подтвердите просмотренный план. Проверьте итоговую транзакцию в журнале пакетного менеджера и ответьте на его запрос."
  ],
  confirmReboot: ["Save your work before rebooting this computer.", "Сохраните работу перед перезагрузкой компьютера."],
  confirmAdditional: ["Review this source’s package list and prompts in the journal.", "Проверьте список пакетов и запросы этого источника в журнале."],
  verified: ["Archives verified", "Архивы проверены"],
  parallel: ["Active downloads", "Активные загрузки"],
  warnings: ["Completed with warnings", "Завершено с предупреждениями"],
  upgrade: ["System upgrade", "Обновление ОС"],
  update: ["Update", "Обновление"],
  remove: ["Remove", "Удаление"],
  reinstall: ["Reinstall", "Повторная установка"],
  hold: ["Hold", "Удержание версии"],
  configure: ["Configure", "Настройка"],
  Upgrading: ["Upgrading", "Обновление"],
  Removing: ["Removing", "Удаление"],
  Replacing: ["Replacing", "Замена"],
  "Installing dependencies": ["Installing dependencies", "Установка зависимостей"],
  "Installing weak dependencies": ["Installing weak dependencies", "Установка необязательных зависимостей"],
  Preparing: ["Preparing", "Подготовка"],
  Configuring: ["Configuring", "Настройка"],
  Downloading: ["Downloading", "Загрузка"],
  Installing: ["Installing", "Установка"],
  Updating: ["Updating", "Обновление"],
  Verifying: ["Verifying", "Проверка"],
  Building: ["Building", "Сборка"],
  Completed: ["Completed", "Завершено"],
  Failed: ["Failed", "Ошибка"],
  Cancelled: ["Cancelled", "Отменено"],
  Cancelling: ["Cancelling", "Отмена"],
  "Waiting for Input": ["Waiting for your response", "Ожидается ваш ответ"],
  "System packages": ["System packages", "Системные пакеты"],
  "Repository transaction": ["Repository transaction", "Транзакция репозиториев"],
  "Pacman transaction": ["Pacman transaction", "Транзакция pacman"],
  "Snapper Btrfs snapshot": ["Snapper Btrfs snapshot", "Снимок Btrfs через Snapper"]
};

const updateLanguage = $("installer-language");
const ut = (key) => updateLabels[key]?.[updateLanguage.value === "ru" ? 1 : 0] ?? key;
const updateSize = (value) => Number.isFinite(value) ? bytes(value) : ut("unknown");
const updateSources = {aur: "aur", "flatpak-user": "flatpakUser", "flatpak-system": "flatpakSystem"};
let updateCursor = 0;
let updateLog = "";
let updateState;
let updatePlanKey;
let updateBusy = false;
let updateManual = false;
let updateConfirmation;
let updateHistory = [];
let updateOnly = false;

function alertUpdate(error) {
  $("updates-error").hidden = !error;
  $("updates-error").textContent = error?.message || "";
}

function updateClick(id, listener) {
  $(id).addEventListener("click", async () => {
    try { await listener(); }
    catch (error) { alertUpdate(error); }
  });
}

function updateFact(key, value) {
  const node = element("div");
  node.append(element("dt", ut(key)), element("dd", value));
  return node;
}

function renderUpdatePlan(state) {
  const plan = state.plan;
  const blocked = updateBusy || state.checking || state.run?.code === null || running;
  const packages = plan?.packages || [];
  const rebootKey = {required: "rebootRequired", clear: "rebootClear", kernel_changed: "kernelChanged",
    kernel_present: "kernelPresent"}[plan?.reboot] || "unknown";
  $("updates-check").disabled = blocked;
  $("updates-install").disabled = blocked || !state.approval;
  $("updates-mode").disabled = blocked;
  $("updates-settings").hidden = state.pm === "void";
  $("updates-mode").querySelector('option[value="adaptive"]').disabled = state.pm !== "pacman";
  $("updates-reboot").hidden = plan?.live !== false || !["rebootRequired", "kernelChanged"].includes(rebootKey);
  $("updates-reboot").disabled = blocked;
  $("updates-desktop").hidden = updateOnly || blocked || !!plan?.error || plan?.live !== false || packages.length > 0 ||
    !plan?.packages || $("existing").dataset.installState !== "fresh";
  const sources = plan?.actions || [];
  $("updates-sources").hidden = plan?.live !== false || (!sources.length && state.pm !== "pacman");
  const aurBlocked = !plan?.packages || packages.length > 0;
  $("updates-aur-hint").hidden = state.pm !== "pacman" || (sources.includes("aur") && !aurBlocked);
  $("updates-aur-hint").textContent = ut(sources.includes("aur") ? "aurWait" : "noAur");
  for (const id of Object.keys(updateSources)) {
    $("updates-" + id).hidden = !sources.includes(id);
    $("updates-" + id).disabled = blocked || (id === "aur" && aurBlocked);
  }
  const planKey = JSON.stringify([state.checking, plan]);
  if (updatePlanKey === planKey) return;
  updatePlanKey = planKey;
  $("updates-mode").value = state.mode;
  $("updates-live").hidden = !plan?.live;
  $("updates-platform").textContent = [plan?.os || $("os").textContent,
    plan?.version || (plan?.os ? ut("rolling") : ""), state.pm === "void" ? "XBPS" : state.pm].filter(Boolean).join(" · ");
  const status = state.checking ? "checking" : plan?.error ? "failedCheck" :
    packages.length ? "available" : plan?.packages ? "current" : "unchecked";
  $("updates-state").textContent = ut(status);
  $("updates-state").dataset.state = plan?.error ? "Failed" : "";
  const shortfall = packages.length && plan.disks?.some(disk => disk.free < disk.required);
  alertUpdate(plan?.error ? new Error(plan.error) : shortfall ? new Error(ut("diskHint")) : null);
  $("updates-facts").replaceChildren(...(plan ? [
    updateFact("repository", plan.error ? ut("unknown") : ut("reachable")),
    updateFact("count", plan.packages ? String(packages.length) : ut("unknown")),
    updateFact("download", updateSize(plan.download)),
    updateFact("change", Number.isFinite(plan.change)
      ? (plan.change < 0 ? "−" : plan.change > 0 ? "+" : "") + updateSize(Math.abs(plan.change)) : ut("unknown")),
    updateFact("security", ut(plan.security === true ? "yes" : plan.security === false ? "no" : "unknown")),
    updateFact("rebootFact", ut(rebootKey))
  ] : []));
  $("updates-packages").replaceChildren(...(packages.length ? packages.map(pkg => element("li", [
    pkg.name, pkg.old ? pkg.old + " → " + pkg.version : pkg.version, pkg.repo, ut(pkg.action || ""),
    Number.isFinite(pkg.size) ? updateSize(pkg.size) : ""
  ].filter(Boolean).join(" · "))) : [element("li", ut(plan?.packages ? "current" : "unknown"))]));
  $("updates-disks").replaceChildren(...(plan?.disks || []).map(disk => element("li", [
    disk.paths.join(", "), updateSize(disk.free) + " " + ut("free"), updateSize(disk.required) + " " + ut("needed")
  ].join(" · "))));
  $("updates-mirrors").hidden = !plan?.error && !plan?.mirrors?.length && !plan?.repos?.length;
  $("updates-diagnostics").textContent = [...(plan?.repos || []), ...(plan?.mirrors || []), plan?.error].filter(Boolean).join("\n");
  $("updates-native").hidden = !plan?.native;
  $("updates-native-text").textContent = plan?.native || "";
}

function renderUpdateRun(state) {
  const run = state.run;
  if (!run) return;
  const journal = $("updates-lines");
  if (updateLog !== run.path) {
    updateLog = run.path;
    updateCursor = 0;
    updateManual = false;
    journal.replaceChildren();
    $("updates-operation").hidden = false;
    $("updates-journal").open = true;
  }
  const follow = journal.scrollHeight - journal.clientHeight - journal.scrollTop < 30;
  for (const [idx, line] of run.lines) {
    updateCursor = Math.max(idx, updateCursor);
    journal.append(document.createTextNode(line + "\n"));
  }
  while (journal.childNodes.length > 800) journal.firstChild.remove();
  if (follow) journal.scrollTop = journal.scrollHeight;
  const inProgress = run.code === null;
  const nativeWarnings = (run.reports || []).flatMap(report => report.native_errors || []);
  const packages = run.downloads || [];
  const queue = run.queue || {};
  const active = packages.filter(pkg => pkg.state === "DOWNLOADING");
  const metrics = run.metrics || {};
  const totalSize = packages.length === queue.total && packages.every(pkg => Number.isFinite(pkg.size))
    ? packages.reduce((total, pkg) => total + pkg.size, 0) : null;
  const verified = packages.filter(pkg => pkg.checksum_verified).length;
  const transferred = packages.reduce((total, pkg) => total + (pkg.received || 0), 0);
  const stage = run.status === "Completed" && nativeWarnings.length ? "warnings" : run.status;
  $("updates-stage").textContent = ut(stage) + " · " + ut(metrics.package || run.component);
  const value = inProgress ? metrics.install_index ?? (queue.stage === "DOWNLOAD" ? transferred : metrics.percent)
    : run.code === 0 ? 100 : null;
  const max = inProgress ? metrics.install_total ?? (queue.stage === "DOWNLOAD" ? totalSize : 100) : 100;
  updateProgress($("updates-progress"), value, max > 0 ? max : null);
  const counters = queue.total !== undefined ? ut("verified") + " " + verified + " / " + queue.total : metrics.count;
  const speed = queue.stage === "DOWNLOAD" ? ut("parallel") + " " + active.length + " / " + (queue.limit || 1) +
    " · " + updateSize(queue.rate || 0) + "/s" : metrics.rate;
  $("updates-rate").textContent = [counters, speed, metrics.size,
    Number.isFinite(metrics.percent) && !queue.stage ? metrics.percent + "%" : null].filter(Boolean).join(" · ");
  $("updates-active").replaceChildren(...active.map(pkg => {
    const row = element("div", "", "queue-active-row");
    const progress = element("progress");
    progress.setAttribute("aria-label", pkg.name);
    updateProgress(progress, pkg.percent, 100);
    row.append(element("strong", pkg.name + " " + pkg.version), progress, element("span", [
      updateSize(pkg.received) + " / " + updateSize(pkg.size),
      Number.isFinite(pkg.percent) ? pkg.percent.toFixed(1) + "%" : null,
      Number.isFinite(pkg.rate) ? updateSize(pkg.rate) + "/s" : null, pkg.mirror
    ].filter(Boolean).join(" · "), "muted"));
    return row;
  }));
  const diagnostics = packages.flatMap(pkg => (pkg.history || [])
    .filter(entry => entry.reason).map(entry => [pkg.name, entry.mirror, entry.reason].join(" · ")));
  $("updates-transfer-errors").hidden = !diagnostics.length && !queue.error && !nativeWarnings.length;
  $("updates-transfer-log").textContent = [...diagnostics, queue.error, ...new Set(nativeWarnings)].filter(Boolean).join("\n");
  $("updates-question").hidden = !inProgress || !(run.prompt || updateManual);
  $("updates-prompt").textContent = run.prompt || run.partial || ut("prompt");
  $("updates-answer").type = run.secret ? "password" : "text";
  $("updates-manual").hidden = !inProgress || !!run.prompt;
  $("updates-retry").hidden = state.operation !== "upgrade" || inProgress || run.code === 0 || state.checking;
  $("updates-export").hidden = inProgress;
  $("updates-failure").hidden = inProgress || run.code === 0;
  $("updates-failure").textContent = queue.error || run.diagnostic || (state.operation === "upgrade" ? ut("mirrorHint") : ut("Failed"));
}

async function pollUpdates() {
  if (closed) return;
  try {
    updateState = await request("/updates/status?" + updateCursor);
    if (closed) return;
    renderUpdatePlan(updateState);
    renderUpdateRun(updateState);
  } catch (error) { alertUpdate(error); }
  setTimeout(pollUpdates, 550);
}

async function updateAction(action, data) {
  if (updateBusy) return;
  updateBusy = true;
  try {
    alertUpdate(null);
    await request("/updates/" + action, data);
    if (action !== "check") {
      updateCursor = 0;
      $("updates-journal").open = true;
      $("updates-operation").hidden = false;
      $("updates-operation").scrollIntoView({ block: "nearest" });
    }
  } finally { updateBusy = false; }
}

function openUpdateConfirmation(action, data, title, body) {
  updateConfirmation = { action, data };
  $("updates-confirm-title").textContent = ut(title);
  $("updates-confirm-body").textContent = ut(body);
  $("updates-confirm-packages").hidden = action !== "upgrade";
  if (action === "upgrade") {
    $("updates-confirm-packages").replaceChildren(...Array.from($("updates-packages").children, node => node.cloneNode(true)));
  }
  $("updates-snapshot-choice").hidden = action !== "upgrade" || !updateState?.plan?.snapshot;
  $("updates-snapshot").checked = false;
  $("updates-confirm").showModal();
}

function showUpdateDetails(button, target) {
  const panel = $(target);
  panel.hidden = !panel.hidden;
  $(button).setAttribute("aria-expanded", String(!panel.hidden));
  return !panel.hidden;
}

function exportSystemReport(report) {
  const url = URL.createObjectURL(new Blob([JSON.stringify(report, null, 2)], { type: "application/json" }));
  const link = element("a");
  link.href = url;
  link.download = report.id.replace(/\.log$/, "") + ".json";
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function renderUpdateHistory() {
  $("updates-history-list").replaceChildren(...updateHistory.map(entry => {
    const item = element("li", [
      new Date(entry.date * 1000).toLocaleString(document.documentElement.lang),
      ut(updateSources[entry.source] || entry.operation), ut(entry.status)
    ].join(" · "));
    const view = element("button", ut("view"), "quiet");
    view.addEventListener("click", async () => {
      try {
        const report = await request("/updates/report?" + encodeURIComponent(entry.id));
        $("updates-history-journal").textContent = report.journal;
        $("updates-history-journal").hidden = false;
      } catch (error) { alertUpdate(error); }
    });
    const exportButton = element("button", ut("export"), "quiet");
    exportButton.addEventListener("click", async () => {
      try { exportSystemReport(await request("/updates/report?" + encodeURIComponent(entry.id))); }
      catch (error) { alertUpdate(error); }
    });
    item.append(view, exportButton);
    return item;
  }));
  if (!updateHistory.length) $("updates-history-list").append(element("li", ut("noHistory")));
}

function localizeUpdates() {
  document.documentElement.lang = updateLanguage.value;
  document.querySelectorAll("[data-update-text]").forEach(node => {
    node.textContent = ut(node.dataset.updateText);
  });
  localizeInstaller();
  updatePlanKey = undefined;
  if (updateState) {
    renderUpdatePlan(updateState);
    renderUpdateRun({ ...updateState, run: updateState.run && { ...updateState.run, lines: [] } });
  }
  if (!$("updates-history").hidden) renderUpdateHistory();
}

updateLanguage.value = localStorage.getItem("serpantinum-installer-language") ||
  (navigator.language.toLowerCase().startsWith("ru") ? "ru" : "en");
updateLanguage.addEventListener("change", () => {
  localStorage.setItem("serpantinum-installer-language", updateLanguage.value);
  localizeUpdates();
});
localizeUpdates();

const checkSystemUpdates = () => updateAction("check", { mode: $("updates-mode").value });
updateClick("updates-check", checkSystemUpdates);
updateClick("updates-retry", checkSystemUpdates);
$("updates-mode").addEventListener("change", () => {
  $("updates-install").disabled = true;
  $("updates-check").click();
});
updateClick("updates-install", () => {
  if (!updateState?.approval) return;
  $("updates-details").hidden = false;
  $("updates-details-button").setAttribute("aria-expanded", "true");
  openUpdateConfirmation("upgrade", { approval: updateState.approval }, "install", "confirmUpgrade");
});
updateClick("updates-details-button", () => showUpdateDetails("updates-details-button", "updates-details"));
updateClick("updates-history-button", async () => {
  if (showUpdateDetails("updates-history-button", "updates-history")) {
    updateHistory = await request("/updates/history");
    $("updates-history-journal").hidden = true;
    renderUpdateHistory();
  }
});
for (const [source, label] of Object.entries(updateSources)) {
  updateClick("updates-" + source, () => openUpdateConfirmation("additional", { source, confirm: true }, label, "confirmAdditional"));
}
updateClick("updates-reboot", () => openUpdateConfirmation("reboot", { confirm: true }, "reboot", "confirmReboot"));
updateClick("updates-desktop", () => {
  $("preparation").scrollIntoView({ block: "start" });
  $("review").focus({ preventScroll: true });
});
updateClick("updates-dismiss", () => $("updates-confirm").close());
updateClick("updates-approve", async () => {
  const { action, data } = updateConfirmation;
  $("updates-confirm").close();
  await updateAction(action, { ...data, snapshot: $("updates-snapshot").checked });
});
updateClick("updates-manual", () => {
  updateManual = true;
  $("updates-question").hidden = false;
  $("updates-answer").focus();
});
$("updates-answer-form").addEventListener("submit", async event => {
  event.preventDefault();
  const answer = $("updates-answer");
  const data = { answer: answer.value, secret: answer.type === "password" };
  answer.value = "";
  try {
    await request("/updates/answer", data);
    updateManual = false;
    $("updates-question").hidden = true;
  } catch (error) { alertUpdate(error); }
});
updateClick("updates-export", async () => {
  exportSystemReport(await request("/updates/report?" + encodeURIComponent(updateLog.split("/").at(-1))));
});
window.addEventListener("installer-ready", event => {
  updateOnly = event.detail.updatesOnly;
  $("desktop-layout").hidden = updateOnly;
  pollUpdates();
});
