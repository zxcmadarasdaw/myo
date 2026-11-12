import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import "../"
import "../../"
import "../../reusables"

GuideTab {
    id: tab
    subTabIndex: 4
    GpuBackendObserver { observerKey: "settings-gpu" }
    property bool previewEnabled: false
    function t(key, en, ru) {
        return I18n.t("gpu." + key, I18n.currentLang === "ru" ? ru : en);
    }
    function pretty(value) { return JSON.stringify(value, null, 2); }
    function recommendationText() {
        if (I18n.currentLang !== "ru") return GpuCompatibility.recommended.reason;
        if (GpuCompatibility.effective.fallback)
            return "Сначала устраните ошибки renderer/шейдеров и отключите безопасный режим. Выбранный профиль сохранён.";
        const report = GpuCompatibility.report;
        if (report.status !== "ok" || !report.gpus || !report.gpus.length)
            return "Данных о GPU пока недостаточно. Balanced — начальный вариант до завершения проверок.";
        if ((report.issues || []).some(function(i) { return i.severity === "warning"; }))
            return "Перед повышением качества устраните предупреждения о драйвере, сеансе и доступе к устройствам.";
        return "Начните с Balanced и проверьте shader preview. Ultra можно попробовать, наблюдая за плавностью на ваших мониторах. Измерения FPS не выполнялись.";
    }
    function issueText(issue) {
        if (I18n.currentLang !== "ru") return issue.message;
        if (issue.code.indexOf("driver-") === 0) return "Не найден привязанный драйвер для " + issue.code.slice(7) + ". Проверьте драйвер вашей системы и журнал ядра.";
        if (issue.code.indexOf("access-") === 0) return "Нет доступного render-узла для " + issue.code.slice(7) + ". Проверьте права текущего сеанса на /dev/dri; не открывайте устройства всем через chmod.";
        const messages = {
            "no-drm": "DRM-устройства не обнаружены. Проверьте /sys/class/drm и драйвер ядра; в контейнере устройства могут быть скрыты.",
            "nvidia-kms": "NVIDIA DRM modeset выключен или его состояние недоступно. Проверьте nvidia_drm.modeset и установленный драйвер.",
            "session": "Сеанс Wayland не подтверждён. Запустите оболочку внутри нужного сеанса Hyprland.",
            "software": "В окружении задан программный рендеринг. Проверьте переменные, если это было сделано не специально.",
            "hypr-ipc": "Hyprland не ответил через IPC. Проверьте hyprctl и принадлежность процесса текущему сеансу.",
            "hypr-config": "Hyprland сообщает об ошибках конфигурации. Подробности находятся в полном отчёте ниже.",
            "hypr-absent": "Сеанс Hyprland не обнаружен; его специальные проверки недоступны.",
            "multi-gpu": "Обнаружено несколько GPU. Мониторы, Qt и декодер могут использовать разные карты. boot_vga не определяет GPU приложения.",
            "overrides": "Заданы параметры выбора GPU/декодера. После замены видеокарты проверьте пути устройств и backend в разделе environment.",
            "platform": "Проверки Linux DRM недоступны на этой ОС. Windows не заменяет тест Fedora/Wayland."
        };
        return messages[issue.code] || issue.message;
    }
    readonly property var gpuList: GpuCompatibility.report.gpus || []
    readonly property var renderNodes: {
        let result = [];
        for (let gpu of gpuList) result = result.concat(gpu.renderNodes || []);
        return result;
    }

    component Info: Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        color: ThemeBackend.text
        font.family: ThemeBackend.fontFamily
        font.pixelSize: tab.rootObj.s(12)
    }
    component Action: Controls.Button {
        font.family: ThemeBackend.fontFamily
        palette.button: ThemeBackend.surface1
        palette.buttonText: ThemeBackend.text
        palette.highlight: ThemeBackend.mauve
    }
    component Heading: Info {
        font.pixelSize: tab.rootObj.s(17)
        font.bold: true
        Layout.topMargin: tab.rootObj.s(12)
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: tab.rootObj.s(12)
        contentWidth: width
        contentHeight: body.implicitHeight + tab.rootObj.s(16)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Controls.ScrollBar.vertical: Controls.ScrollBar {}

        ColumnLayout {
            id: body
            width: parent.width - tab.rootObj.s(14)
            spacing: tab.rootObj.s(10)

            Heading { text: tab.t("title", "GPU compatibility", "Совместимость видеокарт") }
            Info {
                text: tab.t("intro", "Local diagnostics. Drivers are never installed automatically. Profiles do not rewrite your theme, widgets, wallpaper, panel layout or animation settings.", "Локальная диагностика. Драйверы автоматически не устанавливаются. Профили не перезаписывают тему, виджеты, обои, расположение панелей и настройки анимаций.")
            }
            Info {
                visible: GpuCompatibility.hardwareChanged
                color: ThemeBackend.peach
                text: tab.t("changed", "The GPU configuration changed. Review the driver, decoder and environment checks below. Previous GPU: ", "Состав видеокарт изменился. Проверьте драйвер, декодирование и параметры окружения ниже. Раньше: ") + (GpuCompatibility.previousHardware.models || []).join("; ")
            }
            Flow {
                Layout.fillWidth: true
                spacing: tab.rootObj.s(8)
                Action {
                    text: GpuCompatibility.busy ? tab.t("scanning", "Checking…", "Проверка…") : tab.t("refresh", "Refresh diagnostics", "Обновить диагностику")
                    enabled: !GpuCompatibility.busy && Config.dataReady
                    onClicked: GpuCompatibility.scan()
                }
                Action {
                    visible: GpuCompatibility.hardwareChanged
                    text: tab.t("accept", "Acknowledge GPU change", "Подтвердить смену видеокарты")
                    onClicked: GpuCompatibility.acceptHardware()
                }
            }
            Info { visible: GpuCompatibility.scanError !== ""; color: ThemeBackend.red; text: GpuCompatibility.scanError }
            Heading { text: tab.t("profiles", "Graphics profile", "Графический профиль") }
            Flow {
                Layout.fillWidth: true
                spacing: tab.rootObj.s(8)
                Repeater {
                    model: ["Performance", "Balanced", "Ultra"]
                    delegate: Action {
                        required property string modelData
                        text: modelData
                        checkable: true
                        checked: GpuCompatibility.selectedProfile === modelData
                        enabled: Config.dataReady
                        onClicked: GpuCompatibility.setProfile(modelData)
                    }
                }
            }
            Info {
                text: tab.t("cost", "Performance: no wallpaper blur or shader transitions, spectrum 20 FPS. Balanced: 65% of the original backdrop texture dimensions and blur strength, spectrum 30 FPS. Ultra: original effect resolution/strength and spectrum 60 FPS. Video playback and widgets remain available.", "Performance: без размытия обоев и шейдерных переходов, спектр 20 FPS. Balanced: 65% исходных размеров текстур подложки и силы размытия, спектр 30 FPS. Ultra: исходные размеры и сила эффектов, спектр 60 FPS. Видеообои и виджеты остаются доступны.")
            }
            Info {
                text: tab.t("effective", "Effective profile: ", "Действующий профиль: ") + GpuCompatibility.effective.profile
                    + "\n" + tab.t("recommended", "Recommended: ", "Рекомендуется: ") + GpuCompatibility.recommended.profile + "\n" + tab.recommendationText()
            }
            Action {
                text: tab.t("apply", "Apply recommended profile", "Применить рекомендованный профиль")
                enabled: Config.dataReady
                onClicked: GpuCompatibility.setProfile(GpuCompatibility.recommended.profile)
            }
            Controls.CheckBox {
                text: tab.t("safe", "Safe graphics (keep theme settings)", "Безопасная графика (сохранить настройки темы)")
                palette.windowText: ThemeBackend.text
                checked: GpuCompatibility.manualSafeMode
                enabled: Config.dataReady
                onClicked: GpuCompatibility.setSafeMode(checked)
            }
            Info {
                visible: GpuCompatibility.effective.fallback
                color: ThemeBackend.peach
                text: tab.t("fallback", "Fallback active: flat surfaces, plain wallpaper fades, static video snapshots. It can be forced before launch with SERPANTINUM_SAFE_GRAPHICS=1. A Software/Null backend or a recorded shader error also activates it.", "Включено упрощённое отображение: обычные подложки, плавная смена обоев без шейдеров, статичные кадры видео. До запуска его можно включить через SERPANTINUM_SAFE_GRAPHICS=1. Оно также включается при Software/Null backend или ошибке шейдера.")
            }
            Heading { text: tab.t("devices", "Detected GPUs and DRM/KMS", "Обнаруженные GPU и DRM/KMS") }
            Repeater {
                model: tab.gpuList
                delegate: Info {
                    required property var modelData
                    text: modelData.model + "\n" + modelData.vendor + " • PCI " + modelData.address + " • driver: " + modelData.driver
                        + "\nDRM: " + modelData.nodes.map(function(n) { return n.path + (n.accessible ? " [access OK]" : " [no access]"); }).join(", ")
                        + "\nKMS connectors: " + modelData.connectors.map(function(c) { return c.name + " " + c.status + "/" + c.enabled; }).join(", ")
                }
            }
            Info {
                text: "nvidia_drm.modeset: " + (GpuCompatibility.report.nvidiaModeset || "unknown") + "\nQt: " + tab.pretty(GpuCompatibility.backends)
                    + "\n" + tab.t("identity", "Qt's API does not identify its physical GPU. PCI IDs and bound drivers are shown for every generation; no quality rating is inferred from the model name.", "API Qt не определяет физическую GPU. Для любых поколений показываются PCI ID и привязанный драйвер; качество не выбирается по названию модели.")
            }
            Repeater {
                model: GpuCompatibility.report.issues || []
                delegate: Info {
                    required property var modelData
                    color: modelData.severity === "warning" ? ThemeBackend.peach : ThemeBackend.text
                    text: modelData.code + ": " + tab.issueText(modelData)
                }
            }
            Heading { text: "ShaderEffect" }
            Info {
                text: tab.t("shaderHint", "Open the preview: a green rectangle should appear. Compiled status alone does not prove correct pixels or stable performance. If the preview or interface is broken, activate safe graphics.", "Откройте проверку: должен появиться зелёный прямоугольник. Статус compiled сам по себе не доказывает правильное изображение и стабильную скорость. При дефектах изображения включите безопасную графику.")
            }
            Flow {
                Layout.fillWidth: true
                spacing: tab.rootObj.s(8)
                Action {
                    text: tab.t("preview", "Toggle shader preview", "Показать / скрыть проверку шейдера")
                    enabled: GpuCompatibility.shadersAllowed
                    onClicked: tab.previewEnabled = !tab.previewEnabled
                }
                Action {
                    text: tab.t("retry", "Clear shader errors and retry", "Сбросить ошибки шейдеров и повторить")
                    onClicked: GpuCompatibility.resetShaderErrors()
                }
            }
            Loader {
                Layout.preferredWidth: tab.rootObj.s(150)
                Layout.preferredHeight: active ? tab.rootObj.s(45) : 0
                active: tab.isCurrent && tab.previewEnabled && GpuCompatibility.shadersAllowed
                sourceComponent: Item {
                    Rectangle { id: green; anchors.fill: parent; color: "#22cc55" }
                    ShaderEffectSource { id: greenTexture; sourceItem: green; hideSource: true; visible: false }
                    ShaderEffect {
                        anchors.fill: parent
                        property variant src: greenTexture
                        property vector2d itemSize: Qt.vector2d(width, height)
                        property vector4d radii: Qt.vector4d(4, 4, 4, 4)
                        property real fillAlpha: 1
                        fragmentShader: GpuCompatibility.shadersAllowed ? ("file://" + Caching.serpantinumDir + "/assets/shaders/ui/rounded_mask.frag.qsb") : ""
                        onStatusChanged: GpuCompatibility.observeShader("preview", status, log)
                        Component.onCompleted: GpuCompatibility.observeShader("preview", status, log)
                    }
                }
            }
            Info { text: tab.pretty({states: GpuCompatibility.shaderStates, errors: GpuCompatibility.shaderErrors}) }
            Heading { text: tab.t("video", "Video wallpaper and GPU decoding", "Видеообои и аппаратное декодирование") }
            Info {
                text: tab.t("videoHint", "Set a video wallpaper normally, then inspect its Qt playback state below. Playing does not identify the decoder. The optional FFmpeg test reads only the local file you select and discards decoded frames; it does not record your screen.", "Выберите видеообои обычным способом и проверьте состояние Qt ниже. Playing не определяет декодер. Необязательный тест FFmpeg читает указанный локальный файл и отбрасывает кадры; экран он не записывает.")
                    + "\n" + tab.pretty(GpuCompatibility.mediaStates) + "\n" + tab.pretty(GpuCompatibility.report.decode || {status: "unverified"})
            }
            Action {
                text: tab.t("retryVideo", "Retry video wallpapers", "Повторить запуск видеообоев")
                onClicked: GpuCompatibility.retryVideos()
            }
            Controls.TextField {
                id: videoPath
                Layout.fillWidth: true
                placeholderText: tab.t("path", "Absolute path to a local .mp4 / .mkv / .webm / .mov", "Полный путь к локальному .mp4 / .mkv / .webm / .mov")
                selectByMouse: true
            }
            RowLayout {
                Layout.fillWidth: true
                Controls.ComboBox { id: backend; model: ["vaapi", "cuda"] }
                Controls.ComboBox { id: node; Layout.fillWidth: true; visible: backend.currentIndex === 0; model: tab.renderNodes }
                Controls.TextField { id: cudaDevice; Layout.fillWidth: true; visible: backend.currentIndex === 1; text: "0"; placeholderText: "CUDA ordinal (not DRM card number)" }
            }
            Info {
                text: tab.t("decodeHint", "VA-API: choose an accessible render node (typically AMD/Intel). CUDA: enter the NVIDIA CUDA device ordinal. A successful test applies only to this file, GPU and FFmpeg; Qt playback is checked separately.", "VA-API: выберите доступный render-узел (обычно AMD/Intel). CUDA: укажите порядковый номер устройства NVIDIA в CUDA. Успех теста относится только к этому файлу, GPU и FFmpeg; Qt проверяется отдельно.")
            }
            Action {
                text: GpuCompatibility.decodeBusy ? tab.t("decoding", "Decoding…", "Декодирование…") : tab.t("testDecode", "Test GPU decoding", "Проверить аппаратное декодирование")
                enabled: !GpuCompatibility.decodeBusy && videoPath.text.trim() !== ""
                onClicked: GpuCompatibility.decodeFile(videoPath.text.trim(), backend.currentText, backend.currentIndex === 0 ? node.currentText : cudaDevice.text.trim())
            }
            Info { text: tab.pretty(GpuCompatibility.decodeResult) }
            Heading { text: tab.t("recording", "Screen recording availability", "Возможности записи экрана") }
            Info {
                text: tab.t("recordingHint", "Checks installed recording tools and compiled FFmpeg encoders. To verify capture permissions, codec and performance, make a short recording using Serpantinum's existing recorder. This page does not start recording.", "Проверяются установленные средства записи и энкодеры FFmpeg. Для проверки захвата, прав и скорости сделайте короткую запись существующим инструментом Serpantinum. Эта страница запись не запускает.")
                    + "\n" + tab.pretty(GpuCompatibility.report.recording || {status: "unverified"})
            }
            Heading { text: tab.t("details", "Full local diagnostics (select to copy)", "Полная локальная диагностика (можно выделить и скопировать)") }
            Controls.TextArea {
                Layout.fillWidth: true
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                color: ThemeBackend.text
                font.family: ThemeBackend.fontFamily
                font.pixelSize: tab.rootObj.s(11)
                textFormat: TextEdit.PlainText
                background: Rectangle { color: ThemeBackend.surface0; radius: 6 }
                text: tab.pretty(GpuCompatibility.report)
            }
        }
    }
}
