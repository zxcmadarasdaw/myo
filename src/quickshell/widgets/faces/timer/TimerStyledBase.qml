import QtQuick
import "../../../"

// Shared state of the Restrained and Lush timer faces. All three modes come
// from the FocusTimer singleton (the same state as the quick actions timer):
//   0 timer, 1 stopwatch, 2 pomodoro.
Item {
    id: base
    anchors.fill: parent

    property bool previewMode: false
    property real minWidth: 160
    property real minHeight: 90
    property real maxWidth: 800
    property real maxHeight: 700
    property real minAspect: 0.7
    property real maxAspect: 4.0
    property bool isRound: false

    readonly property int mode: FocusTimer.activeMode
    readonly property bool interactive: !previewMode

    readonly property bool running: mode === 0 ? FocusTimer.isTimerRunning
        : mode === 1 ? FocusTimer.isStopwatchRunning : FocusTimer.isPomoRunning

    readonly property real displayMs: mode === 0 ? FocusTimer.timerRemainingMs
        : mode === 1 ? FocusTimer.swDisplayMs : FocusTimer.pomoRemainingMs

    readonly property string timeText: FocusTimer.formatTime(displayMs, false)

    readonly property real pomoPhaseMs: (FocusTimer.pomoState === 0 ? FocusTimer.pomoWorkLimit
        : FocusTimer.pomoState === 1 ? FocusTimer.pomoShortBreakLimit : FocusTimer.pomoLongBreakLimit) * 60 * 1000

    // 0..1; the stopwatch shows the position within the current minute
    readonly property real progress: mode === 0 ? (FocusTimer.timerPresetMs > 0 ? 1 - FocusTimer.timerRemainingMs / FocusTimer.timerPresetMs : 0)
        : mode === 1 ? (FocusTimer.swDisplayMs % 60000) / 60000
        : (pomoPhaseMs > 0 ? 1 - FocusTimer.pomoRemainingMs / pomoPhaseMs : 0)

    readonly property var modeNames: [
        I18n.t("quickactions.timer.tabs.timer", "Timer"),
        I18n.t("quickactions.timer.tabs.stopwatch", "Stopwatch"),
        I18n.t("quickactions.timer.tabs.pomodoro", "Pomodoro")
    ]

    readonly property string phaseText: mode !== 2 ? ""
        : FocusTimer.pomoState === 0 ? I18n.t("widgets.timer.focus", "Focus")
        : FocusTimer.pomoState === 1 ? I18n.t("widgets.timer.shortBreak", "Short break")
        : I18n.t("widgets.timer.longBreak", "Long break")

    // second action: reset (timer), lap/reset (stopwatch), skip phase (pomodoro)
    readonly property string secondaryIcon: mode === 0 ? "↺" : mode === 1 ? (running ? "◷" : "↺") : "⏭"
    readonly property string secondaryName: mode === 0 ? I18n.t("widgets.timer.reset", "Reset")
        : mode === 1 ? (running ? I18n.t("widgets.timer.lap", "Lap") : I18n.t("widgets.timer.reset", "Reset"))
        : I18n.t("widgets.timer.skip", "Skip")

    function toggle() {
        if (!base.interactive) return;
        FocusTimer.toggleMode(base.mode);
    }

    function secondary() {
        if (!base.interactive) return;
        if (base.mode === 0) FocusTimer.resetTimer();
        else if (base.mode === 1) FocusTimer.stopwatchLapOrReset();
        else FocusTimer.skipPomoPhase();
    }

    function selectMode(m) {
        if (!base.interactive || m === base.mode) return;
        FocusTimer.setActiveMode(m);
    }
}
