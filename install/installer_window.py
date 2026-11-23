"""Native Qt interface for the existing Serpantinum installation worker."""

from concurrent.futures import ThreadPoolExecutor
import os
import signal
import subprocess
import sys

from manager import COMPOSITORS, DEFAULT_OPTIONS, OPTIONS, OPTIONS_RU


def desktop(manager_factory):
    try:
        from PySide6 import QtCore, QtWidgets
    except ImportError:
        try:
            from PyQt6 import QtCore, QtWidgets
        except ImportError:
            print("Qt Python bindings are unavailable. Use --tui or install the distribution's Qt 6 bindings.", file=sys.stderr)
            return False

    app = QtWidgets.QApplication(sys.argv[:1])
    app.setApplicationName("Serpantinum Installer")
    interrupted = False

    def request_stop(_signal, _frame):
        nonlocal interrupted
        interrupted = True

    class Window(QtWidgets.QWidget):
        def __init__(self):
            super().__init__()
            self.manager = self.task = self.on_result = None
            self.finished_run = None
            self.pool = ThreadPoolExecutor(max_workers=1)
            self.cursor = 0
            self.russian = os.environ.get("LC_ALL", os.environ.get("LC_MESSAGES", os.environ.get("LANG", ""))).startswith("ru")
            self.resize(820, 430)
            layout = QtWidgets.QVBoxLayout(self)
            layout.setContentsMargins(18, 16, 18, 16)
            layout.setSpacing(10)
            top = QtWidgets.QHBoxLayout()
            self.title = QtWidgets.QLabel("Serpantinum")
            title_font = self.title.font()
            title_font.setPointSize(21)
            self.title.setFont(title_font)
            top.addWidget(self.title)
            top.addStretch()
            self.language = QtWidgets.QComboBox()
            self.language.addItems(["English", "Русский"])
            self.language.setCurrentIndex(int(self.russian))
            self.language.currentIndexChanged.connect(self.translate)
            top.addWidget(self.language)
            layout.addLayout(top)
            self.platform = QtWidgets.QLabel()
            self.platform.setWordWrap(True)
            layout.addWidget(self.platform)
            actions = QtWidgets.QHBoxLayout()
            self.buttons = {}
            for action in ("prepare", "install", "verify", "repair"):
                button = self.buttons[action] = QtWidgets.QPushButton()
                button.setMinimumHeight(32)
                button.clicked.connect(lambda checked=False, key=action: self.review(key))
                actions.addWidget(button)
            layout.addLayout(actions)
            self.advanced = QtWidgets.QCheckBox()
            layout.addWidget(self.advanced)
            self.details = QtWidgets.QTabWidget()
            self.details.setVisible(False)
            self.advanced.toggled.connect(self.details.setVisible)
            layout.addWidget(self.details, 1)
            self.journal = QtWidgets.QPlainTextEdit(readOnly=True)
            self.journal.document().setMaximumBlockCount(2000)
            self.journal.setLineWrapMode(QtWidgets.QPlainTextEdit.LineWrapMode.NoWrap)
            self.packages = QtWidgets.QPlainTextEdit(readOnly=True)
            self.details.addTab(self.journal, "")
            self.details.addTab(self.packages, "")
            settings = QtWidgets.QWidget()
            form = QtWidgets.QGridLayout(settings)
            self.compositors = {}
            for index, name in enumerate(COMPOSITORS):
                box = self.compositors[name] = QtWidgets.QCheckBox(name)
                box.setChecked(name == "hyprland")
                form.addWidget(box, 0, index)
            self.options = {}
            for index, name in enumerate(OPTIONS):
                box = self.options[name] = QtWidgets.QCheckBox()
                box.setChecked(name in DEFAULT_OPTIONS)
                form.addWidget(box, 1 + index // 2, index % 2 * 2, 1, 2)
            self.mode = QtWidgets.QComboBox()
            self.mode.addItems(["stable", "balanced", "fast", "adaptive"])
            self.mode.setCurrentIndex(1)
            form.addWidget(self.mode, 11, 0, 1, 2)
            for index, action in enumerate(("update", "missing")):
                button = self.buttons[action] = QtWidgets.QPushButton()
                button.clicked.connect(lambda checked=False, key=action: self.review(key))
                form.addWidget(button, 12, index * 2, 1, 2)
            self.details.addTab(settings, "")
            self.status = QtWidgets.QLabel()
            self.status.setWordWrap(True)
            self.status.setTextFormat(QtCore.Qt.TextFormat.PlainText)
            self.latest = QtWidgets.QLabel()
            self.latest.setWordWrap(True)
            self.latest.setTextFormat(QtCore.Qt.TextFormat.PlainText)
            self.latest.setTextInteractionFlags(QtCore.Qt.TextInteractionFlag.TextSelectableByMouse)
            layout.addWidget(self.status)
            layout.addWidget(self.latest)
            self.prompt = QtWidgets.QLabel()
            self.prompt.setWordWrap(True)
            self.prompt.setTextFormat(QtCore.Qt.TextFormat.PlainText)
            layout.addWidget(self.prompt)
            self.input_row = QtWidgets.QWidget()
            response = QtWidgets.QHBoxLayout(self.input_row)
            response.setContentsMargins(0, 0, 0, 0)
            self.answer = QtWidgets.QLineEdit()
            self.answer.returnPressed.connect(self.send)
            response.addWidget(self.answer)
            self.send_button = QtWidgets.QPushButton()
            self.send_button.clicked.connect(self.send)
            response.addWidget(self.send_button)
            layout.addWidget(self.input_row)
            controls = QtWidgets.QHBoxLayout()
            self.cancel = QtWidgets.QPushButton()
            self.cancel.clicked.connect(lambda: self.manager.run.cancel())
            self.retry = QtWidgets.QPushButton()
            self.retry.clicked.connect(lambda: self.start("retry"))
            self.resume = QtWidgets.QPushButton()
            self.resume.clicked.connect(lambda: self.review("saved"))
            self.launch = QtWidgets.QPushButton()
            self.launch.clicked.connect(self.launch_shell)
            for button in (self.cancel, self.retry, self.resume, self.launch):
                controls.addWidget(button)
            controls.addStretch()
            layout.addLayout(controls)
            self.simple_space = QtWidgets.QWidget()
            layout.addWidget(self.simple_space, 1)
            self.advanced.toggled.connect(lambda advanced: self.simple_space.setVisible(not advanced))
            self.translate(int(self.russian))
            self.submit(manager_factory, self.set_manager)
            self.timer = QtCore.QTimer(self)
            self.timer.timeout.connect(self.poll)
            self.timer.start(100)

        def tr_text(self, english, russian):
            return russian if self.russian else english

        def translate(self, index):
            self.russian = bool(index)
            tr = self.tr_text
            self.setWindowTitle(tr("Serpantinum Installer", "Установщик Serpantinum"))
            for key, labels in {
                "prepare": ("Prepare system", "Подготовить систему"),
                "install": ("Install Serpantinum", "Установить Serpantinum"),
                "verify": ("Verify", "Проверить установку"),
                "repair": ("Repair", "Восстановить установку"),
                "update": ("Update", "Обновить"),
                "missing": ("Install missing", "Установить недостающее"),
            }.items():
                self.buttons[key].setText(tr(*labels))
            self.advanced.setText(tr("Advanced", "Расширенный режим"))
            for index, labels in enumerate([("Journal", "Журнал"), ("Packages", "Пакеты"), ("Options", "Параметры")]):
                self.details.setTabText(index, tr(*labels))
            for key, english in OPTIONS.items():
                self.options[key].setText(tr(english, OPTIONS_RU[key]))
            self.mode.setToolTip(tr("Native download parallelism", "Параллельность штатной загрузки"))
            self.send_button.setText(tr("Send", "Отправить"))
            self.cancel.setText(tr("Cancel", "Отменить"))
            self.retry.setText(tr("Retry step", "Повторить этап"))
            self.resume.setText(tr("Review saved plan", "Открыть сохранённый план"))
            self.launch.setText(tr("Launch Serpantinum", "Запустить Serpantinum"))
            self.answer.setPlaceholderText(tr("Response to the current command", "Ответ выполняемой команде"))

        def submit(self, operation, callback):
            self.task = self.pool.submit(operation)
            self.on_result = callback
            self.status.setText(self.tr_text("Checking the system and package plan…", "Проверка системы и списка пакетов…"))
            self.refresh_controls()

        def set_manager(self, manager):
            self.manager = manager
            inventory = manager.inventory
            os_name, distro, backend, version, _, _ = inventory["meta"][0]
            self.platform.setText(f"{os_name} ({distro}) · {backend} · Serpantinum {version}")
            for option in ("sync", "aur"):
                self.options[option].setVisible(backend == "pacman")
            self.options["sync"].setEnabled(not any(row[0] == "live" for row in inventory["session"]))
            self.default_compositors = inventory["selected"][0][0].split() or ["hyprland"]
            for name, box in self.compositors.items():
                box.setChecked(name in self.default_compositors)
            self.show_packages(inventory)
            self.status.setText(self.tr_text("Choose an action.", "Выберите действие."))
            self.latest.setText("\n".join(row[0] for row in inventory["warning"] + inventory["error"]))

        def show_packages(self, records):
            self.packages.setPlainText("\n".join(" · ".join(row) for row in records["package"]))

        def review(self, action):
            advanced = self.advanced.isChecked()
            plan = dict(action="install" if action == "prepare" else action,
                        compositors=[name for name, box in self.compositors.items() if box.isChecked()] if advanced else self.default_compositors,
                        options=[name for name, box in self.options.items() if box.isChecked() and box.isEnabled() and not box.isHidden()] if advanced else list(DEFAULT_OPTIONS),
                        download_mode=self.mode.currentText() if advanced else "balanced")
            self.submit(lambda: self.manager.review(plan, saved=action == "saved"),
                        lambda records: self.show_review(action, records))

        def show_review(self, action, records):
            tr = self.tr_text
            self.show_packages(records)
            changes = [row[0] for row in records["error"] + records["warning"] + records["change"]]
            changes.extend(f"{path}: {free} KiB ({minimum} KiB min.)" for path, minimum, free in records["disk"])
            if action == "verify":
                changes.extend(" · ".join(row) for row in records["component"])
            if not changes:
                changes = [tr("Check the selected compositor, configuration, launcher and shell dependencies.",
                              "Проверить выбранный композитор, конфиги, команду запуска и зависимости оболочки.")]
            text = "\n".join(changes)
            self.status.setText(tr("Plan is ready.", "План готов.") if records["approval"] else tr("The plan is blocked.", "План заблокирован."))
            self.latest.setText(changes[0])
            dialog = QtWidgets.QMessageBox(self)
            dialog.setWindowTitle(tr("Installation plan", "План установки"))
            dialog.setTextFormat(QtCore.Qt.TextFormat.PlainText)
            dialog.setText(self.status.text())
            dialog.setDetailedText(text)
            dialog.setInformativeText("\n".join(changes[:3]))
            approve = None
            if records["approval"] and action != "prepare":
                approve = dialog.addButton(tr("Run", "Выполнить"), QtWidgets.QMessageBox.ButtonRole.AcceptRole)
            close = dialog.addButton(QtWidgets.QMessageBox.StandardButton.Close)
            dialog.setDefaultButton(close)
            dialog.exec()
            if approve is not None and dialog.clickedButton() == approve:
                self.start(approval=records["approval"])

        def start(self, mode="start", approval=None):
            try:
                self.manager.start(mode, approval=approval)
            except (OSError, ValueError) as exc:
                self.show_error(exc)
                return
            self.journal.clear()
            self.latest.clear()
            self.answer.clear()
            self.cursor = 0
            self.refresh_controls()

        def show_error(self, exc):
            self.status.setText(self.tr_text("Operation failed.", "Ошибка операции."))
            self.latest.setText(str(exc))

        def send(self):
            run = self.manager.run
            try:
                run.answer(self.answer.text(), run.secret)
            except (OSError, ValueError) as exc:
                self.show_error(exc)
            finally:
                self.answer.clear()

        def launch_shell(self):
            try:
                self.manager.launch()
            except (OSError, ValueError) as exc:
                self.show_error(exc)
            else:
                self.status.setText(self.tr_text("Launch requested.", "Отправлена команда запуска."))

        def refresh_controls(self):
            run = self.manager.run if self.manager else None
            active = run is not None and run.exit_code is None
            idle = self.manager is not None and not active and self.task is None
            for button in self.buttons.values():
                button.setEnabled(idle)
            self.input_row.setVisible(active and not run.cancelled)
            self.cancel.setVisible(active)
            self.retry.setVisible(idle and run is not None and (run.exit_code != 0 or run.cancelled))
            self.resume.setVisible(idle and self.manager.saved() is not None)
            self.launch.setVisible(idle and run is not None and run.exit_code == 0 and not run.cancelled)

        def poll(self):
            tr = self.tr_text
            if interrupted:
                run = self.manager.run if self.manager else None
                if run is not None and run.exit_code is None:
                    run.cancel()
                elif self.task is None or self.task.done():
                    app.quit()
                    return
            if self.task and self.task.done():
                task, self.task = self.task, None
                try:
                    self.on_result(task.result())
                except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
                    self.show_error(exc)
                self.refresh_controls()
            if not self.manager or not self.manager.run or self.task or self.manager.run is self.finished_run:
                return
            self.manager.update()
            state = self.manager.run.state(self.cursor)
            if state["lines"]:
                self.journal.appendPlainText("\n".join(line for _, line in state["lines"]))
                self.cursor = state["lines"][-1][0]
            self.answer.setEchoMode(QtWidgets.QLineEdit.EchoMode.Password if state["secret"] else QtWidgets.QLineEdit.EchoMode.Normal)
            self.send_button.setEnabled(not self.manager.run.reply_in_flight)
            self.prompt.setText(state["prompt"] or (state["partial"] if state["code"] is None else ""))
            metrics = state["metrics"]
            progress = [metrics.get(key) for key in ("package", "count", "rate")]
            native_total = state["queue"].get("total")
            if native_total and not metrics.get("count"):
                progress.append(tr(f"{native_total} packages", f"Пакетов: {native_total}"))
            if metrics.get("percent") is not None:
                progress.append(f"{metrics['percent']:g}%")
            if state["total"]:
                progress.insert(0, f"{state['phase']}/{state['total']}")
            status = state["status"]
            translated = {
                "Preparing": "Подготовка", "Waiting for Input": "Ожидание ответа", "Installing": "Установка",
                "Downloading": "Загрузка", "Updating": "Обновление", "Configuring": "Настройка",
                "Verifying": "Проверка", "Building": "Сборка", "Cancelling": "Отмена",
                "Cancelled": "Отменено", "Completed": "Завершено", "Failed": "Ошибка",
            }
            label = tr(status, translated.get(status, status))
            if status == "Completed" and any(report.get("native_errors") for report in state["reports"]):
                label = tr("Completed with warnings", "Завершено с предупреждениями")
            if state["code"] is None:
                progress.append(tr(f"No output for {state['idle']} s", f"Без вывода {state['idle']} с"))
                if state["idle"] >= 15 and state["processes"]:
                    progress.append(", ".join(state["processes"]))
            self.status.setText(" · ".join(filter(None, [label, state["component"], *progress])))
            detail = "\n".join(filter(None, [state["latest"], state["diagnostic"], self.manager.launch_error, state["path"]]))
            self.latest.setText(detail)
            if state["code"] is not None:
                self.finished_run = self.manager.run
            self.refresh_controls()

        def closeEvent(self, event):
            if self.manager and self.manager.run and self.manager.run.exit_code is None:
                self.manager.run.cancel()
                event.ignore()
                return
            if self.task and not self.task.done():
                event.ignore()
                return
            event.accept()

    window = Window()
    window.show()
    handlers = {number: signal.signal(number, request_stop) for number in (signal.SIGINT, signal.SIGTERM, getattr(signal, "SIGHUP", None))
                if number is not None}
    try:
        app.exec()
    finally:
        for number, handler in handlers.items():
            signal.signal(number, handler)
        if window.manager:
            window.manager.cancel_and_wait()
        window.pool.shutdown(wait=False, cancel_futures=True)
    if interrupted:
        raise KeyboardInterrupt
    return True
