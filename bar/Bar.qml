pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Effects
import "../config"
import "../services"
import "../components"
import "./popouts" as Popouts

Scope {
    id: root

    component PillText: Text {
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: Theme.text
        anchors.verticalCenter: parent.verticalCenter
    }

    // Стрелка на Bluetooth-пилюле: переключает наушники/клавиатуру. Свой
    // клик перехватывает у пилюли, как иконки трея
    component Arrow: MouseArea {
        id: arrow
        property int step: 1
        visible: Buds.list.length > 1
        width: arrowText.implicitWidth
        height: arrowText.implicitHeight
        anchors.verticalCenter: parent.verticalCenter
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Buds.cycle(step)

        PillText {
            id: arrowText
            text: arrow.step < 0 ? "‹" : "›"
            color: arrow.containsMouse ? Theme.text : Theme.overlay1
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: perScreen
            required property var modelData

        PanelWindow {
            id: win
            screen: perScreen.modelData

            anchors { top: true; left: true; right: true }
            implicitHeight: Settings.barHeight + Settings.popoutMaxHeight + Settings.popoutWing
            exclusiveZone: Settings.barHeight
            color: "transparent"
            WlrLayershell.namespace: "quickshell:bar"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: win.popoutOpen && win.shownPopout === "launcher"
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // ===== Состояние попаутов =====
            property string shownPopout: ""   // что загружено в Loader
            property bool popoutOpen: false   // целевое состояние (высота)
            property string queuedPopout: ""
            property Item popAnchor: null
            property Item queuedAnchor: null
            property real popAnchorX: 0
            // Попауты, которые висят от правого края своей пилюли, а не по центру
            readonly property var rightAligned: ["music"]
            property bool popAlignRight: false
            property bool everHovered: false

            // Пока открыт любой попаут — всплывашки уведомлений молчат
            onPopoutOpenChanged: Ui.openPopouts += popoutOpen ? 1 : -1
            Component.onDestruction: if (popoutOpen) Ui.openPopouts--

            // Точка привязки: центр пилюли или её правый край
            function placeAt(name, anchor) {
                popAlignRight = rightAligned.includes(name)
                popAnchorX = !anchor ? width / 2
                    : anchor.mapToItem(null, popAlignRight ? anchor.width : anchor.width / 2, 0).x
            }

            // Старое меню полностью закрывается, потом открывается новое
            function togglePopout(name, anchor) {
                if (popoutOpen) {
                    if (shownPopout === name) {
                        queuedPopout = ""
                        popoutOpen = false
                    } else {
                        queuedPopout = name
                        queuedAnchor = anchor
                        popoutOpen = false
                    }
                } else if (shownPopout !== "" && popoutFrame.height > 0) {
                    // идёт анимация закрытия — ставим в очередь
                    queuedPopout = name
                    queuedAnchor = anchor
                } else {
                    shownPopout = name
                    popAnchor = anchor
                    placeAt(name, anchor)
                    everHovered = false
                    popoutOpen = true
                }
            }

            function popoutFullyClosed() {
                if (queuedPopout !== "") {
                    shownPopout = queuedPopout
                    popAnchor = queuedAnchor
                    placeAt(queuedPopout, queuedAnchor)
                    queuedPopout = ""
                    queuedAnchor = null
                    everHovered = false
                    popoutOpen = true
                } else {
                    shownPopout = ""
                    popAnchor = null
                }
            }

            // Ввод принимают только бар и открытое меню — остальное прозрачно
            mask: Region {
                item: barRect
                Region { item: popoutFrame }
            }

            Connections {
                target: Ui

                function onClosePopouts() {
                    win.queuedPopout = ""
                    win.popoutOpen = false
                }

                function anchorFor(name) {
                    const anchors = {
                        launcher: logoPill, calendar: timePill, weather: weatherPill, system: sysPill,
                        music: musicPill, volume: volumePill, battery: batteryPill,
                        bluetooth: btPill, notifications: notifPill
                    }
                    return anchors[name]
                }

                function onPopoutRequested(name) {
                    const anchor = anchorFor(name)
                    if (anchor !== undefined)
                        win.togglePopout(name, anchor)
                }

                function onPopoutOpenRequested(name) {
                    const anchor = anchorFor(name)
                    if (anchor !== undefined && !(win.popoutOpen && win.shownPopout === name))
                        win.togglePopout(name, anchor)
                }

                function onPopoutCloseRequested(name) {
                    if (win.queuedPopout === name)
                        win.queuedPopout = ""
                    else if (win.popoutOpen && win.shownPopout === name)
                        win.popoutOpen = false
                }
            }

            // Взаимодействие с другими окнами закрывает меню
            Connections {
                target: Compositor

                function onFocusedWindowIdChanged() {
                    // Игнорируем: -1 (фокус на layer-shell) и любые события,
                    // пока курсор на баре/меню — иначе клики внутри закрывают попаут
                    if (Compositor.focusedWindowId === -1 || barHover.hovered)
                        return
                    win.queuedPopout = ""
                    win.popoutOpen = false
                }

                function onOverviewOpenChanged() {
                    if (Compositor.overviewOpen) {
                        win.queuedPopout = ""
                        win.popoutOpen = false
                    }
                }
            }

            // Автозакрытие, когда мышь ушла с бара и меню.
            // Поверх всего (z) — иначе MouseArea внутри меню перехватывают
            // hover и barHover.hovered ложно падает в false
            Item {
                anchors.fill: parent
                z: 1000
                HoverHandler { id: barHover; blocking: false }
            }

            Timer {
                interval: 800
                running: win.popoutOpen && win.everHovered && !barHover.hovered
                    && win.shownPopout !== "launcher"
                onTriggered: win.popoutOpen = false
            }

            Connections {
                target: barHover
                function onHoveredChanged() {
                    if (barHover.hovered && win.popoutOpen)
                        win.everHovered = true
                }
            }

            // ===== Подложка шелла =====
            // Все фоны (бар, попаут, крылья, уголки) отдельно от содержимого:
            // между ними ложится свет обложки, а силуэт подложки его обрезает
            Item {
                id: backdrop
                anchors.fill: parent

                Rectangle {
                    width: parent.width
                    height: Settings.barHeight
                    color: Theme.barBg
                }

                // Фон попаута повторяет его рамку (та обрезает содержимое)
                Rectangle {
                    x: popoutFrame.x
                    y: popoutFrame.y
                    width: popoutFrame.width
                    height: popoutFrame.height
                    color: Theme.popoutBg
                    bottomLeftRadius: popoutFrame.flushLeft ? 0 : popoutFrame.corner
                    bottomRightRadius: popoutFrame.flushRight ? 0 : popoutFrame.corner
                }

                // ===== Внутренние углы к краям монитора =====
                InnerCorner {
                    x: 0
                    y: Settings.barHeight
                }
                InnerCorner {
                    x: win.width - width
                    y: Settings.barHeight
                    flipX: true
                }

                // "Крылья" попаута — бесшовный переход к бару
                InnerCorner {
                    visible: !popoutFrame.flushLeft
                    x: popoutFrame.x - width
                    y: Settings.barHeight
                    radius: popoutFrame.wing
                    flipX: true
                }
                InnerCorner {
                    visible: !popoutFrame.flushRight
                    x: popoutFrame.x + popoutFrame.width
                    y: Settings.barHeight
                    radius: popoutFrame.wing
                }

                // Прилипшее к краю меню перетекает внутренним углом в грань экрана
                InnerCorner {
                    visible: popoutFrame.flushLeft
                    x: 0
                    y: Settings.barHeight + popoutFrame.height
                    radius: popoutFrame.wing
                }
                InnerCorner {
                    visible: popoutFrame.flushRight
                    x: win.width - width
                    y: Settings.barHeight + popoutFrame.height
                    radius: popoutFrame.wing
                    flipX: true
                }
            }

            // ===== Свет обложки =====
            // Размытая обложка из попаута музыки, на весь шелл: под содержимым,
            // над фоном, по силуэту подложки. Режется только внешним краем шелла
            Item {
                id: shellGlow
                anchors.fill: parent

                readonly property Item src: loader.item?.glowSource ?? null
                readonly property bool on: src !== null && (loader.item?.glowOn ?? false)
                    && win.popoutOpen

                opacity: on ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 250 } }

                // Эффекты живут, только пока свет виден: без обложки им
                // нечего рисовать, а пустые эффекты сыпят предупреждениями
                Loader {
                    anchors.fill: parent
                    active: shellGlow.visible
                    sourceComponent: Item {
                        ShaderEffectSource {
                            id: shellShape
                            anchors.fill: parent
                            sourceItem: backdrop
                            visible: false
                            live: shellGlow.visible
                        }

                        Item {
                            id: glowLight
                            anchors.fill: parent
                            visible: false
                            layer.enabled: shellGlow.visible

                            MultiEffect {
                                readonly property point pos: loader.item?.glowPos ?? Qt.point(0, 0)
                                x: popoutFrame.x + pos.x
                                y: popoutFrame.y + pos.y
                                width: shellGlow.src?.width ?? 0
                                height: shellGlow.src?.height ?? 0
                                source: shellGlow.src
                                blurEnabled: true
                                blur: 1
                                blurMax: Settings.glowBlur
                                saturation: Settings.glowSaturation
                                brightness: Settings.glowBrightness
                                scale: Settings.glowScale
                            }
                        }

                        MultiEffect {
                            id: glowShaped
                            anchors.fill: parent
                            source: glowLight
                            maskEnabled: true
                            maskSource: shellShape
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1
                            layer.enabled: shellGlow.visible
                        }

                        // Дизеринг: тайловый шум по альфе света, против полос в градиенте
                        Image {
                            id: glowNoise
                            anchors.fill: parent
                            source: Qt.resolvedUrl("../assets/noise.png")
                            fillMode: Image.Tile
                            smooth: false
                            visible: false
                        }
                        MultiEffect {
                            anchors.fill: parent
                            source: glowNoise
                            maskEnabled: true
                            maskSource: glowShaped
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1
                            opacity: Dither.glowNoise
                        }
                    }
                }
            }

            // ===== Бар =====
            Rectangle {
                id: barRect
                width: parent.width
                height: Settings.barHeight
                color: "transparent"   // фон — в backdrop

                // --- Левая часть ---
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Settings.barSpacing

                    BarPill {
                        id: logoPill
                        anchors.verticalCenter: parent.verticalCenter
                        active: win.shownPopout === "launcher"
                        onClicked: win.togglePopout("launcher", logoPill)

                        Image {
                            source: Qt.resolvedUrl("../assets/nixos.png")
                            width: 18; height: 18
                            anchors.verticalCenter: parent.verticalCenter
                            smooth: true
                        }
                    }

                    BarPill {
                        id: timePill
                        anchors.verticalCenter: parent.verticalCenter
                        active: win.shownPopout === "calendar"
                        onClicked: win.togglePopout("calendar", timePill)

                        PillText { text: "󰥔"; color: Theme.sapphire }
                        PillText { text: Time.time }
                    }

                    BarPill {
                        id: weatherPill
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Weather.ready
                        active: win.shownPopout === "weather"
                        onClicked: win.togglePopout("weather", weatherPill)

                        PillText { text: Weather.icon; color: Weather.colorOf(Weather.code, Weather.isDay) }
                        PillText { text: Weather.fmt(Weather.temp) }
                    }

                    // Яркость: только тусклый значок, процент выезжает
                    // при наведении и когда яркость меняют
                    BarPill {
                        id: brightPill
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Brightness.present
                        onWheeled: delta => Brightness.change(delta / 120 * 0.05)

                        // Тап на сенсоре/тачпаде оставляет «наведение» навсегда —
                        // после клика ховер не раскрывает, пока курсор не уйдёт
                        property bool tapped: false
                        onHoveredChanged: if (!hovered) tapped = false
                        onClicked: { tapped = true; brightShow.restart() }
                        readonly property bool expanded: (hovered && !tapped) || brightShow.running

                        Timer {
                            id: brightShow
                            interval: 1500
                        }
                        Connections {
                            target: Brightness
                            function onPercentChanged() { brightShow.restart() }
                        }

                        PillText {
                            text: Brightness.icon
                            color: brightPill.expanded ? Theme.yellow : Theme.overlay1
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: brightPill.expanded ? brightText.implicitWidth : -6
                            height: brightText.implicitHeight
                            clip: true
                            Behavior on width {
                                Spring {}
                            }

                            PillText {
                                id: brightText
                                text: Brightness.percent.toString()
                                opacity: brightPill.expanded ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                        }
                    }

                    // Bluetooth: значок, а с наушниками — их заряд (левый · правый).
                    // СКМ — включить/выключить адаптер
                    BarPill {
                        id: btPill
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Bt.present || Buds.current !== null
                        active: win.shownPopout === "bluetooth"
                        onClicked: event => {
                            if (event.button === Qt.MiddleButton)
                                Bt.toggle()
                            else
                                win.togglePopout("bluetooth", btPill)
                        }

                        readonly property var budsBattery: Buds.ready ? Buds.current.battery ?? {} : {}
                        readonly property var levels: (Buds.current?.caps?.battery ?? [])
                            .filter(k => k !== "case" && budsBattery[k])
                            .map(k => budsBattery[k])
                        // Без управляемых наушников — заряд, который отдал BlueZ
                        readonly property var other: Bt.connected.find(d => d.batteryAvailable) ?? null

                        onWheeled: delta => Buds.cycle(delta > 0 ? -1 : 1)

                        Arrow { step: -1 }
                        PillText {
                            text: !Buds.current ? Bt.icon
                                : Buds.current.caps?.kind === "keyboard" ? "󰌌" : "󰋋"
                            color: Buds.ready ? Theme.sapphire
                                 : !Bt.enabled ? Theme.overlay0
                                 : Bt.connected.length > 0 ? Theme.sapphire : Theme.overlay1
                        }
                        PillText {
                            visible: btPill.levels.length > 0
                            text: btPill.levels.map(b => b.level).join(" · ")
                            color: btPill.levels.some(b => b.charging) ? Theme.green : Theme.text
                        }
                        PillText {
                            visible: btPill.levels.length === 0 && btPill.other !== null
                            text: Math.round((btPill.other?.battery ?? 0) * 100).toString()
                        }
                        Arrow { step: 1 }
                    }

                    BarPill {
                        id: windowPill
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Compositor.focusedWindow !== null
                        onClicked: Compositor.toggleOverview()

                        PillText { text: "Window:"; color: Theme.overlay1 }
                        GradientText {
                            anchors.verticalCenter: parent.verticalCenter
                            pixelSize: Theme.fontSize
                            maxChars: 40
                            text: Compositor.focusedWindow?.title ?? ""
                        }
                    }

                    // Идёт запись экрана или кто-то слушает микрофон.
                    // Клик останавливает трансляции экрана (PipeWire)
                    BarPill {
                        id: recPill
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Record.active
                        interactive: Record.screen
                        onClicked: Record.stopAll()

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8; height: 8; radius: 4
                            color: Theme.red
                            SequentialAnimation on opacity {
                                running: recPill.visible
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                            }
                        }
                        PillText {
                            visible: Record.screen
                            text: "󰍹"
                            color: Theme.red
                        }
                        PillText {
                            visible: Record.screen
                            text: Record.screenLabel + "  " + Record.elapsed
                        }
                        PillText {
                            visible: Record.mic
                            text: "󰍬"
                            color: Theme.peach
                        }
                        PillText {
                            visible: Record.mic && !Record.screen
                            text: Record.micUsers.join(", ")
                        }
                    }
                }

                // --- Центр ---
                Row {
                    anchors.centerIn: parent
                    spacing: Settings.barSpacing

                    BarPill {
                        id: sysPill
                        anchors.verticalCenter: parent.verticalCenter
                        active: win.shownPopout === "system"
                        onClicked: win.togglePopout("system", sysPill)

                        PillText { text: ""; color: Theme.blue }
                        PillText { text: SysStat.cpu.toFixed(0) }
                        PillText { text: ""; color: Theme.blue }
                        PillText { text: SysStat.memPerc.toFixed(0) }
                        PillText { text: "󰔏"; color: Theme.blue }
                        PillText { text: SysStat.temp.toFixed(0) }
                    }

                    BarPill {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: (Compositor.currentLang ?? "") !== ""
                        onClicked: Compositor.switchLayout()

                        PillText { text: Compositor.langShort }
                    }
                }

                // --- Правая часть ---
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Settings.barSpacing

                    BarPill {
                        id: musicPill
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Players.active !== null
                        active: win.shownPopout === "music"
                        onClicked: event => {
                            if (event.button === Qt.MiddleButton)
                                Players.active?.togglePlaying()
                            else
                                win.togglePopout("music", musicPill)
                        }

                        PillText {
                            text: Players.playing ? "󰏤" : "󰐊"
                            color: Theme.mauve
                        }
                        ScrollClip {
                            id: artistScroll
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Players.artist !== ""
                            maxWidth: 140
                            fadeColor: musicPill.color

                            PillText {
                                id: pillArtist
                                text: Players.artist
                                color: Theme.subtext1
                                onTextChanged: artistScroll.reset()
                                Behavior on text { TextFade { target: pillArtist } }
                            }
                        }
                        PillText { text: "–"; color: Theme.overlay0; visible: Players.artist !== "" }
                        ScrollClip {
                            id: titleScroll
                            anchors.verticalCenter: parent.verticalCenter
                            maxWidth: 170
                            fadeColor: musicPill.color

                            GradientText {
                                id: pillTitle
                                anchors.verticalCenter: parent.verticalCenter
                                pixelSize: Theme.fontSize
                                text: Players.title
                                onTextChanged: titleScroll.reset()
                                Behavior on text { TextFade { target: pillTitle } }
                            }
                        }
                        PillText { text: "| " + Players.timeText; color: Theme.overlay1 }
                    }

                    BarPill {
                        id: volumePill
                        anchors.verticalCenter: parent.verticalCenter
                        active: win.shownPopout === "volume"
                        onClicked: event => {
                            if (event.button === Qt.MiddleButton)
                                Audio.toggleMute()
                            else
                                win.togglePopout("volume", volumePill)
                        }
                        // Плавный скролл: 1% на щелчок колеса
                        onWheeled: delta => Audio.change(delta / 120 * 0.01)

                        PillText {
                            text: Audio.icon
                            color: Audio.muted ? Theme.overlay0 : Theme.teal
                        }
                        PillText {
                            text: Audio.muted ? "MUTED" : Math.round(Audio.volume * 100).toString()
                            color: Audio.muted ? Theme.overlay0 : Theme.text
                        }
                    }

                    BarPill {
                        id: batteryPill
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Power.present
                        active: win.shownPopout === "battery"
                        onClicked: win.togglePopout("battery", batteryPill)

                        PillText { text: Power.percent.toString() }
                        PillText {
                            text: Power.icon
                            color: Power.critical ? Theme.red
                                 : Power.charging ? Theme.green : Theme.text
                        }
                    }

                    BarPill {
                        id: trayPill
                        anchors.verticalCenter: parent.verticalCenter
                        // Апплеты, которые повторяют пилюли шелла (Settings.trayHidden)
                        readonly property var items: SystemTray.items.values.filter(i => !Settings.trayHidden
                            .some(h => (i.id + " " + i.title).toLowerCase().includes(h.toLowerCase())))
                        visible: items.length > 0
                        active: win.shownPopout === "tray"

                        Repeater {
                            model: trayPill.items

                            MouseArea {
                                id: trayIcon
                                required property SystemTrayItem modelData
                                width: 18; height: 18
                                anchors.verticalCenter: parent.verticalCenter
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                cursorShape: Qt.PointingHandCursor

                                IconImage {
                                    anchors.fill: parent
                                    source: trayIcon.modelData.icon
                                }

                                onClicked: event => {
                                    // ЛКМ/ПКМ — меню, СКМ — activate
                                    if (event.button === Qt.MiddleButton) {
                                        trayIcon.modelData.activate()
                                    } else if (trayIcon.modelData.hasMenu) {
                                        Ui.trayMenuHandle = trayIcon.modelData.menu
                                        win.togglePopout("tray", trayIcon)
                                    } else {
                                        trayIcon.modelData.activate()
                                    }
                                }
                            }
                        }
                    }

                    BarPill {
                        id: notifPill
                        anchors.verticalCenter: parent.verticalCenter
                        active: win.shownPopout === "notifications"
                        onClicked: event => {
                            if (event.button === Qt.MiddleButton)
                                Notifs.toggleDnd()
                            else
                                win.togglePopout("notifications", notifPill)
                        }

                        PillText {
                            text: Notifs.icon
                            color: Notifs.dnd ? Theme.overlay0
                                 : Notifs.unread && Notifs.count > 0 ? Theme.peach : Theme.lavender
                        }
                        PillText {
                            text: Notifs.count.toString()
                            visible: Notifs.count > 0
                            color: Notifs.dnd ? Theme.overlay0 : Theme.text
                        }
                    }
                }
            }

            // ===== Попаут =====
            Item {
                id: popoutFrame

                readonly property real contentW: Math.ceil(loader.item?.implicitWidth ?? 200)
                readonly property real contentH: Math.min(
                    loader.item?.implicitHeight ?? 0, Settings.popoutMaxHeight)
                // фиксируется при открытии, чтобы попаут не скакал при смене контента пилюли
                readonly property real anchorX: win.popAnchorX

                // Прилипание к краям: у самого края меню сливается с гранью экрана
                readonly property real snapZone: Settings.screenRadius + Settings.popoutWing + 8
                // Целые пиксели: иначе между меню и «крылом» светится щель в 1px
                readonly property real rawX: Math.round(win.popAlignRight ? anchorX - contentW : anchorX - contentW / 2)
                readonly property bool flushLeft: rawX < snapZone
                readonly property bool flushRight: rawX + contentW > win.width - snapZone

                // Пока меню низкое, углы и крылья растут/тают вместе с высотой:
                // открывается и закрывается капля, а не прямоугольная полоска
                readonly property real wing: Math.min(Settings.popoutWing, height)
                readonly property real corner: Math.min(Settings.popoutRadius, height / 2)

                y: Settings.barHeight
                width: contentW
                height: win.popoutOpen ? contentH : 0
                clip: true
                x: flushLeft ? 0
                 : flushRight ? win.width - contentW
                 : rawX


                // Открытие пружинит, закрытие — без перелёта (высота не уходит в минус)
                Behavior on height {
                    Spring { id: heightSpring; bouncy: win.popoutOpen }
                }

                onHeightChanged: {
                    if (height === 0 && !win.popoutOpen)
                        win.popoutFullyClosed()
                }

                // Поэлементное появление (PopoutReveal). Элементы ищем
                // рекурсивно: контейнер дробится на детей, если они стоят друг
                // под другом. Если у контейнера свой фон (карточка), фон
                // открывается краем сразу, а проявляются его строки. Детали
                // бок о бок и строка списка — один элемент
                property var revealTargets: []

                // Без ShaderEffectSource: такие заводит layer.enabled, это
                // внутренности чужого слоя, а не содержимое
                function visibleKids(n) {
                    return Array.from(n.children).filter(c => c.visible && c.width > 0 && c.height > 0
                        && c.sourceItem === undefined)
                }

                // Ничего не рисует сам: Item/Column/Row или прозрачный Rectangle
                function isPlain(n) {
                    if (n.text !== undefined || n.source !== undefined)
                        return false
                    if (n.color !== undefined)
                        return n.color.a === 0 && !(n.border && n.border.width > 0) && !n.gradient
                    return true
                }

                function stacked(kids) {
                    const k = kids.slice().sort((a, b) => a.y - b.y)
                    for (let i = 1; i < k.length; i++)
                        if (k[i].y >= k[i - 1].y + k[i - 1].height - 1)
                            return true
                    return false
                }

                function findElements(node, depth) {
                    depth = depth ?? 0
                    if (!node)
                        return []
                    // Строки списка — целиком
                    if (node.contentItem && node.model !== undefined && node.flicking !== undefined) {
                        const rows = visibleKids(node.contentItem)
                        if (rows.length === 0)
                            listPending = true
                        return rows.length > 0 ? rows : [node]
                    }
                    // Сцена (revealWhole) проявляется целиком: её частицы
                    // разбросаны по высоте и сошли бы за строки, а свои
                    // opacity и сдвиги у них отнимать нельзя
                    if (node.revealWhole === true)
                        return [node]
                    const kids = visibleKids(node)
                    if (depth > 8 || kids.length === 0)
                        return [node]
                    if (kids.length === 1)
                        return findElements(kids[0], depth + 1)
                    if (!stacked(kids))
                        return [node]
                    return kids.reduce((all, k) => all.concat(findElements(k, depth + 1)), [])
                }

                // Столбцы раскладывают, а списки создают строки не сразу после
                // загрузки — ждём пару кадров, а до тех пор содержимое прячем
                property bool listPending: false
                property int scanTries: 0
                Timer {
                    id: revealScan
                    interval: 40
                    onTriggered: {
                        popoutFrame.listPending = false
                        const found = popoutFrame.findElements(loader.item)
                        // Список ещё не создал строки — подождём ещё немного
                        if (popoutFrame.listPending && ++popoutFrame.scanTries < 6) {
                            restart()
                            return
                        }
                        popoutFrame.revealTargets = found
                        loader.opacity = 1
                    }
                }

                Instantiator {
                    model: popoutFrame.revealTargets
                    delegate: PopoutReveal {
                        container: loader.item
                        edge: popoutFrame.height
                        full: popoutFrame.contentH
                        open: win.popoutOpen
                    }
                }

                Behavior on x {
                    enabled: win.popoutOpen && popoutFrame.height > 0
                    Spring {}
                }

                Loader {
                    id: loader
                    onLoaded: {
                        opacity = 0
                        popoutFrame.scanTries = 0
                        revealScan.restart()
                    }
                    onItemChanged: if (!item) popoutFrame.revealTargets = []
                    sourceComponent: {
                        switch (win.shownPopout) {
                        case "launcher": return launcherComp
                        case "calendar": return calendarComp
                        case "weather": return weatherComp
                        case "system": return systemComp
                        case "music": return musicComp
                        case "volume": return volumeComp
                        case "battery": return batteryComp
                        case "bluetooth": return bluetoothComp
                        case "tray": return trayComp
                        case "notifications": return notificationsComp
                        default: return null
                        }
                    }
                }
            }

            Component { id: launcherComp; Popouts.LauncherPopout {} }
            Component { id: calendarComp; Popouts.CalendarPopout {} }
            Component { id: weatherComp; Popouts.WeatherPopout {} }
            Component { id: systemComp; Popouts.SystemPopout {} }
            Component { id: musicComp; Popouts.MusicPopout {} }
            Component { id: volumeComp; Popouts.VolumePopout {} }
            Component { id: batteryComp; Popouts.BatteryPopout {} }
            Component { id: bluetoothComp; Popouts.BluetoothPopout {} }
            Component { id: trayComp; Popouts.TrayMenuPopout {} }
            Component { id: notificationsComp; Popouts.NotificationsPopout {} }
        }

        // Прозрачный ловец кликов на весь экран: клик мимо меню закрывает его.
        // Дырки в маске — бар и само меню, туда клики проходят насквозь.
        PanelWindow {
            id: catcher
            screen: perScreen.modelData
            visible: win.popoutOpen || popoutFrame.height > 0
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "quickshell:clickcatcher"
            WlrLayershell.layer: WlrLayer.Top

            mask: Region {
                x: 0; y: 0
                width: catcher.width; height: catcher.height

                Region {
                    intersection: Intersection.Subtract
                    x: 0; y: 0
                    width: catcher.width; height: Settings.barHeight
                }
                Region {
                    intersection: Intersection.Subtract
                    x: popoutFrame.x - Settings.popoutWing
                    y: Settings.barHeight
                    width: popoutFrame.width + Settings.popoutWing * 2
                    height: popoutFrame.height + Settings.popoutWing
                }
            }

            MouseArea {
                anchors.fill: parent
                onPressed: {
                    win.queuedPopout = ""
                    win.popoutOpen = false
                }
            }
        }
        }
    }
}
