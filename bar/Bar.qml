pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import QtQuick
import ".."
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
            property bool everHovered: false

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
                    popAnchorX = anchor ? anchor.mapToItem(null, anchor.width / 2, 0).x : width / 2
                    everHovered = false
                    popoutOpen = true
                }
            }

            function popoutFullyClosed() {
                if (queuedPopout !== "") {
                    shownPopout = queuedPopout
                    popAnchor = queuedAnchor
                    popAnchorX = queuedAnchor ? queuedAnchor.mapToItem(null, queuedAnchor.width / 2, 0).x : width / 2
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

                function onPopoutRequested(name) {
                    const anchors = {
                        launcher: logoPill, calendar: timePill, system: sysPill,
                        music: musicPill, volume: volumePill, battery: batteryPill
                    }
                    if (anchors[name] !== undefined)
                        win.togglePopout(name, anchors[name])
                }
            }

            // Взаимодействие с другими окнами закрывает меню
            Connections {
                target: Niri

                function onFocusedWindowIdChanged() {
                    // Игнорируем: -1 (фокус на layer-shell) и любые события,
                    // пока курсор на баре/меню — иначе клики внутри закрывают попаут
                    if (Niri.focusedWindowId === -1 || barHover.hovered)
                        return
                    win.queuedPopout = ""
                    win.popoutOpen = false
                }

                function onOverviewOpenChanged() {
                    if (Niri.overviewOpen) {
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

            // ===== Бар =====
            Rectangle {
                id: barRect
                width: parent.width
                height: Settings.barHeight
                color: Theme.barBg

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
                        id: windowPill
                        anchors.verticalCenter: parent.verticalCenter
                        interactive: false
                        visible: Niri.focusedWindow !== null

                        PillText { text: "Window:"; color: Theme.overlay1 }
                        GradientText {
                            anchors.verticalCenter: parent.verticalCenter
                            pixelSize: Theme.fontSize
                            maxChars: 40
                            text: Niri.focusedWindow?.title ?? ""
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

                        PillText { text: "󰻠"; color: Theme.green }
                        PillText { text: SysStat.cpu.toFixed(0) }
                        PillText { text: "󰍛"; color: Theme.blue }
                        PillText { text: SysStat.memPerc.toFixed(0) }
                        PillText { text: "󰔏"; color: Theme.peach }
                        PillText { text: SysStat.temp.toFixed(0) }
                    }

                    BarPill {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: (Niri.currentLang ?? "") !== ""
                        onClicked: Niri.switchLayout()

                        PillText {
                            text: {
                                const l = Niri.currentLang ?? ""
                                if (l.indexOf("Russian") !== -1 || l.indexOf("рус") !== -1)
                                    return "RU"
                                if (l.indexOf("English") !== -1)
                                    return "EN"
                                return l.substring(0, 2).toUpperCase()
                            }
                        }
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
                        PillText {
                            text: {
                                const a = Players.artist
                                return a.length > 20 ? a.substring(0, 19) + "…" : a
                            }
                            visible: text !== ""
                            color: Theme.subtext1
                        }
                        PillText { text: "–"; color: Theme.overlay0; visible: Players.artist !== "" }
                        GradientText {
                            anchors.verticalCenter: parent.verticalCenter
                            pixelSize: Theme.fontSize
                            maxChars: 20
                            text: Players.title
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
                        visible: SystemTray.items.values.length > 0
                        active: win.shownPopout === "tray"

                        Repeater {
                            model: SystemTray.items

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
                }
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

            // ===== Попаут =====
            Item {
                id: popoutFrame

                readonly property real contentW: loader.item?.implicitWidth ?? 200
                readonly property real contentH: Math.min(
                    loader.item?.implicitHeight ?? 0, Settings.popoutMaxHeight)
                // фиксируется при открытии, чтобы попаут не скакал при смене контента пилюли
                readonly property real anchorX: win.popAnchorX

                // Прилипание к краям: у самого края меню сливается с гранью экрана
                readonly property real snapZone: Settings.screenRadius + Settings.popoutWing + 8
                readonly property real rawX: anchorX - contentW / 2
                readonly property bool flushLeft: rawX < snapZone
                readonly property bool flushRight: rawX + contentW > win.width - snapZone

                y: Settings.barHeight
                width: contentW
                height: win.popoutOpen ? contentH : 0
                clip: true
                x: flushLeft ? 0
                 : flushRight ? win.width - contentW
                 : rawX

                onHeightChanged: {
                    if (height === 0 && !win.popoutOpen)
                        win.popoutFullyClosed()
                }

                Behavior on height {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
                Behavior on x {
                    enabled: win.popoutOpen && popoutFrame.height > 0
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                Rectangle {
                    anchors.fill: parent
                    color: Theme.popoutBg
                    bottomLeftRadius: popoutFrame.flushLeft ? 0 : Settings.popoutRadius
                    bottomRightRadius: popoutFrame.flushRight ? 0 : Settings.popoutRadius
                }

                Loader {
                    id: loader
                    sourceComponent: {
                        switch (win.shownPopout) {
                        case "launcher": return launcherComp
                        case "calendar": return calendarComp
                        case "system": return systemComp
                        case "music": return musicComp
                        case "volume": return volumeComp
                        case "battery": return batteryComp
                        case "tray": return trayComp
                        default: return null
                        }
                    }
                }
            }

            // "Крылья" попаута — бесшовный переход к бару
            InnerCorner {
                visible: !popoutFrame.flushLeft
                x: popoutFrame.x - width
                y: Settings.barHeight
                radius: Settings.popoutWing
                flipX: true
                opacity: win.popoutOpen && win.shownPopout !== "" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
            InnerCorner {
                visible: !popoutFrame.flushRight
                x: popoutFrame.x + popoutFrame.width
                y: Settings.barHeight
                radius: Settings.popoutWing
                opacity: win.popoutOpen && win.shownPopout !== "" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }

            // Прилипшее к краю меню перетекает внутренним углом в грань экрана
            InnerCorner {
                visible: popoutFrame.flushLeft
                x: 0
                y: Settings.barHeight + popoutFrame.height
                radius: Settings.popoutWing
                opacity: win.popoutOpen && win.shownPopout !== "" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
            InnerCorner {
                visible: popoutFrame.flushRight
                x: win.width - width
                y: Settings.barHeight + popoutFrame.height
                radius: Settings.popoutWing
                flipX: true
                opacity: win.popoutOpen && win.shownPopout !== "" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }

            Component { id: launcherComp; Popouts.LauncherPopout {} }
            Component { id: calendarComp; Popouts.CalendarPopout {} }
            Component { id: systemComp; Popouts.SystemPopout {} }
            Component { id: musicComp; Popouts.MusicPopout {} }
            Component { id: volumeComp; Popouts.VolumePopout {} }
            Component { id: batteryComp; Popouts.BatteryPopout {} }
            Component { id: trayComp; Popouts.TrayMenuPopout {} }
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
