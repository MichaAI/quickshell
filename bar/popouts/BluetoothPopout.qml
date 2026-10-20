pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Bluetooth
import "../../config"
import "../../services"
import "../../components"

// Bluetooth: адаптер, устройства и — если подключены наушники, которыми
// умеет управлять budsd, — их батарея и настройки. Контролы рисуются из
// caps, которые прислал демон (см. tools/budsd/src/drivers/mod.rs): попаут
// не знает, какие у тебя уши.
Item {
    id: root

    implicitWidth: 380
    implicitHeight: Math.min(col.implicitHeight + 28, Settings.popoutMaxHeight)

    readonly property var buds: Buds.current
    readonly property var controls: buds?.caps?.controls ?? []
    readonly property var values: buds?.values ?? ({})

    // showIf: {"<id>": значение} — все должны совпасть
    function shown(c) {
        return Object.keys(c.showIf ?? {}).every(k => values[k] === c.showIf[k])
    }

    readonly property var tabMeta: ({
        noise: { icon: "󰋎", label: "Шум" },
        sound: { icon: "󰎈", label: "Звук" },
        gestures: { icon: "󰆽", label: "Жесты" },
        more: { icon: "󰒓", label: "Ещё" },
        devices: { icon: "󰂯", label: "Устройства" }
    })
    readonly property var pages: buds
        ? ["noise", "sound", "gestures", "more"].filter(p => controls.some(c => c.page === p)).concat(["devices"])
        : []
    property string page: ""
    readonly property string tab: pages.includes(page) ? page : (pages[0] ?? "devices")

    Component.onDestruction: Bt.scan(false)

    // ===== Мелкие детали =====

    component HeadBtn: Rectangle {
        property alias label: t.text
        property bool on: false
        signal pressed()
        width: 32; height: 32; radius: on ? 16 : 10
        Behavior on radius { Spring {} }
        color: on ? Theme.alpha(Theme.gradEnd, 0.22) : hma.containsMouse ? Theme.cardBg : "transparent"
        Text {
            id: t
            anchors.centerIn: parent
            font.family: Theme.font
            font.pixelSize: 16
            color: parent.on ? Theme.gradEnd : hma.containsMouse ? Theme.text : Theme.overlay1
        }
        MouseArea {
            id: hma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.pressed()
        }
    }

    component Label: Text {
        font.family: Theme.font
        font.pixelSize: 11
        color: Theme.overlay1
    }

    // Тональная кнопка MD3E: пилюля, нажатая — квадратнее
    component TonalBtn: Rectangle {
        id: tb
        property alias text: tbt.text
        property bool on: false
        signal pressed()
        implicitWidth: tbt.implicitWidth + 32
        height: 36
        radius: tma.pressed ? 10 : 18
        Behavior on radius { Spring {} }
        color: on ? Theme.alpha(Theme.gradStart, 0.3) : tma.containsMouse ? Theme.surface1 : Theme.surface0
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            id: tbt
            anchors.centerIn: parent
            font.family: Theme.font
            font.pixelSize: 12
            color: tb.on ? Theme.gradStart : Theme.text
        }
        MouseArea {
            id: tma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tb.pressed()
        }
    }

    // ===== Контролы из caps =====

    // Встряхнуть item, если откатилась настройка id (или жест с этим префиксом)
    component Rollback: Connections {
        required property string ctl
        required property var item
        target: Buds
        function onFailed(device, id, message) {
            if (id === ctl || id.startsWith(ctl + "."))
                item.shake()
        }
    }

    Component {
        id: choiceComp

        Column {
            id: choice
            readonly property var c: parent.ctl
            readonly property bool chipStyle: c.style === "chips"
            spacing: 6

            Label { text: choice.c.label }
            ButtonGroup {
                id: group
                visible: !choice.chipStyle
                width: choice.width
                tall: choice.c.id === "noise"
                options: choice.c.options
                current: root.values[choice.c.id]
                onPicked: id => Buds.set(choice.c.id, id)
            }
            ChipGroup {
                id: chips
                visible: choice.chipStyle
                width: choice.width
                options: choice.c.options
                current: root.values[choice.c.id]
                onPicked: id => Buds.set(choice.c.id, id)
            }
            Rollback { ctl: choice.c.id; item: choice.chipStyle ? chips : group }
        }
    }

    component ToggleRow: Item {
        id: tr
        property string icon: ""
        property string label: ""
        property string note: ""
        property bool checked: false
        signal toggled(bool on)
        function shake() { sw.shake() }

        width: parent.width
        height: Math.max(44, texts.implicitHeight + 12)

        Text {
            id: ico
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            text: tr.icon
            font.family: Theme.font
            font.pixelSize: 16
            color: tr.checked ? Theme.gradEnd : Theme.overlay1
            Behavior on color { ColorAnimation { duration: 150 } }
        }
        Column {
            id: texts
            anchors.left: ico.right
            anchors.leftMargin: 10
            anchors.right: sw.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: tr.label
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: 13
                color: Theme.text
            }
            Text {
                width: parent.width
                visible: tr.note !== ""
                text: tr.note
                wrapMode: Text.WordWrap
                font.family: Theme.font
                font.pixelSize: 11
                color: Theme.overlay1
            }
        }
        Md3Switch {
            id: sw
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: tr.checked
            onToggled: on => tr.toggled(on)
        }
        MouseArea {
            anchors.fill: texts
            cursorShape: Qt.PointingHandCursor
            onClicked: tr.toggled(!tr.checked)
        }
    }

    Component {
        id: toggleComp

        ToggleRow {
            id: row
            readonly property var c: parent.ctl
            icon: c.icon ?? ""
            label: c.label
            note: c.note ?? ""
            checked: root.values[c.id] === true
            onToggled: on => Buds.set(c.id, on)
            Rollback { ctl: row.c.id; item: row }
        }
    }

    Component {
        id: levelComp

        Column {
            id: levelCol
            readonly property var c: parent.ctl
            readonly property int min: c.min
            readonly property int max: c.max
            readonly property int val: root.values[c.id] ?? min
            spacing: 4

            Item {
                width: levelCol.width
                height: 16
                Label { text: levelCol.c.label }
                Text {
                    anchors.right: parent.right
                    text: levelCol.val + " / " + levelCol.max
                    font.family: Theme.font
                    font.pixelSize: 11
                    color: Theme.subtext1
                }
            }
            StyledSlider {
                width: levelCol.width
                steps: levelCol.max - levelCol.min
                value: (levelCol.val - levelCol.min) / Math.max(1, levelCol.max - levelCol.min)
                // Наушникам — одно значение, когда отпустили; колесо — списку
                live: false
                wheelEnabled: false
                valueText: v => Math.round(levelCol.min + v * (levelCol.max - levelCol.min))
                onMoved: v => {
                    const n = Math.round(levelCol.min + v * (levelCol.max - levelCol.min))
                    if (n !== levelCol.val)
                        Buds.set(levelCol.c.id, n)
                }
            }
        }
    }

    Component {
        id: bandsComp

        Column {
            id: bandsCol
            readonly property var c: parent.ctl
            readonly property var val: root.values[c.id] ?? [0, 0, 0]
            spacing: 2

            Label { text: bandsCol.c.label }
            Repeater {
                model: bandsCol.c.bands

                Item {
                    id: band
                    required property string modelData
                    required property int index
                    width: bandsCol.width
                    height: 36

                    readonly property real lo: bandsCol.c.min
                    readonly property real hi: bandsCol.c.max
                    readonly property real db: bandsCol.val[index] ?? 0

                    Text {
                        id: bandName
                        width: 72
                        anchors.verticalCenter: parent.verticalCenter
                        text: band.modelData
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: Theme.subtext1
                    }
                    StyledSlider {
                        anchors.left: bandName.right
                        anchors.right: dbText.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        steps: band.hi - band.lo
                        value: (band.db - band.lo) / (band.hi - band.lo)
                        live: false
                        wheelEnabled: false
                        valueText: v => {
                            const n = Math.round(band.lo + v * (band.hi - band.lo))
                            return (n > 0 ? "+" : "") + n + " дБ"
                        }
                        onMoved: v => {
                            const n = Math.round(band.lo + v * (band.hi - band.lo))
                            if (n === band.db)
                                return
                            const next = bandsCol.val.slice()
                            next[band.index] = n
                            Buds.set(bandsCol.c.id, next)
                        }
                    }
                    Text {
                        id: dbText
                        width: 40
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: (band.db > 0 ? "+" : "") + band.db + " дБ"
                        font.family: Theme.font
                        font.pixelSize: 11
                        color: Theme.text
                    }
                }
            }
        }
    }

    Component {
        id: gesturesComp

        Column {
            id: gest
            readonly property var c: parent.ctl
            property string side: c.sides[0].id
            property string open: ""
            spacing: 6

            ButtonGroup {
                width: parent.width
                options: gest.c.sides
                current: gest.side
                onPicked: id => gest.side = id
            }

            Repeater {
                model: gest.c.gestures

                Rectangle {
                    id: g
                    required property var modelData
                    readonly property string key: "gesture." + gest.side + "." + modelData.id
                    readonly property var val: root.values[key] ?? ({})
                    readonly property var option: modelData.options.find(o => o.id === val.action)
                    readonly property bool expanded: gest.open === modelData.id

                    width: gest.width
                    height: gcol.implicitHeight + 20
                    radius: expanded ? 20 : 12
                    Behavior on radius { Spring {} }
                    Behavior on height { Spring {} }
                    clip: true
                    color: Theme.cardBg

                    Rollback { ctl: g.key; item: modes.visible ? modes : actions }

                    Column {
                        id: gcol
                        x: 12
                        y: 10
                        width: parent.width - 24
                        spacing: 8

                        Item {
                            width: parent.width
                            height: 34

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    text: g.modelData.label
                                    font.family: Theme.font
                                    font.pixelSize: 13
                                    color: Theme.text
                                }
                                Text {
                                    text: !g.option ? "—"
                                        : g.val.action === "noise"
                                            ? (g.val.cycle ?? []).map(m => g.option.modes.find(x => x.id === m)?.label ?? m).join(" → ")
                                            : g.option.label
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    color: Theme.gradEnd
                                }
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰅀"
                                rotation: g.expanded ? 180 : 0
                                Behavior on rotation { Spring {} }
                                font.family: Theme.font
                                font.pixelSize: 16
                                color: Theme.overlay1
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: gest.open = g.expanded ? "" : g.modelData.id
                            }
                        }

                        ChipGroup {
                            id: actions
                            visible: g.expanded
                            width: parent.width
                            options: g.modelData.options
                            current: g.val.action
                            onPicked: id => {
                                const o = g.modelData.options.find(x => x.id === id)
                                if (o.cycle)
                                    Buds.set(g.key, { action: id, cycle: g.val.cycle ?? ["transparency", "anc"] })
                                else
                                    Buds.set(g.key, { action: id })
                            }
                        }

                        Label {
                            visible: modes.visible
                            text: "Переключать по кругу"
                        }
                        ChipGroup {
                            id: modes
                            visible: g.expanded && (g.option?.cycle ?? false)
                            width: parent.width
                            multi: true
                            options: g.option?.modes ?? []
                            current: g.val.cycle ?? []
                            onPicked: id => {
                                const cur = g.val.cycle ?? []
                                const next = cur.includes(id) ? cur.filter(x => x !== id) : cur.concat([id])
                                // Меньше двух режимов — переключать нечего
                                if (next.length < 2) {
                                    modes.shake()
                                    return
                                }
                                Buds.set(g.key, { action: "noise", cycle: next })
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: devicesComp

        Column {
            readonly property var c: parent.ctl
            spacing: 4

            Label { text: parent.c.label }
            Repeater {
                model: root.buds?.devices ?? []

                Item {
                    id: dd
                    required property var modelData
                    width: parent.width
                    height: 40

                    Text {
                        id: ddIcon
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        text: dd.modelData.self ? "󰟀" : "󰄜"
                        font.family: Theme.font
                        font.pixelSize: 15
                        color: dd.modelData.connected ? Theme.gradEnd : Theme.overlay1
                    }
                    Column {
                        anchors.left: ddIcon.right
                        anchors.leftMargin: 10
                        anchors.right: ddBtn.left
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: dd.modelData.name || dd.modelData.mac
                            font.family: Theme.font
                            font.pixelSize: 12
                            color: Theme.text
                        }
                        Text {
                            text: (dd.modelData.self ? "Этот компьютер · " : "")
                                + (dd.modelData.connected ? "подключено" : "не подключено")
                            font.family: Theme.font
                            font.pixelSize: 10
                            color: Theme.overlay1
                        }
                    }
                    TonalBtn {
                        id: ddBtn
                        visible: !dd.modelData.self
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: dd.modelData.connected ? "Отключить" : "Подключить"
                        onPressed: Buds.act("dualConnect", { mac: dd.modelData.mac, connect: !dd.modelData.connected })
                    }
                }
            }
        }
    }

    Component {
        id: ringComp

        Column {
            id: rc
            readonly property var c: parent.ctl
            // Звенящие стороны: наушники сами о звоне не сообщают
            property var ringing: []
            spacing: 6

            Label { text: rc.c.label }
            Row {
                spacing: 8
                Repeater {
                    model: rc.c.sides

                    TonalBtn {
                        required property var modelData
                        readonly property bool ringing: rc.ringing.includes(modelData.id)
                        on: ringing
                        text: (ringing ? "󰓛 " : "󰂞 ") + modelData.label
                        onPressed: {
                            const on = !ringing
                            rc.ringing = on ? rc.ringing.concat([modelData.id]) : rc.ringing.filter(x => x !== modelData.id)
                            Buds.act("ring", { side: modelData.id, on: on })
                        }
                    }
                }
            }
            // Ушёл со страницы или закрыл попаут — не оставлять звенеть
            Component.onDestruction: {
                for (const side of ringing)
                    Buds.act("ring", { side: side, on: false })
            }
        }
    }

    Component {
        id: fitComp

        Column {
            id: fc
            readonly property var c: parent.ctl
            property bool running: false
            property var result: null
            spacing: 6

            Label { text: fc.c.label }
            Row {
                spacing: 10
                TonalBtn {
                    text: fc.running ? "󰔟 Слушаю…" : "󰐊 Проверить"
                    on: fc.running
                    onPressed: {
                        if (fc.running)
                            return
                        fc.running = true
                        fc.result = null
                        Buds.act("fitTest", {}, (err, res) => {
                            fc.running = false
                            fc.result = err ? null : res
                        })
                    }
                }
                Repeater {
                    model: fc.result ? [["Левый", fc.result.left], ["Правый", fc.result.right]] : []
                    Text {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData[0] + ": " + ({ good: "сидит", bad: "поправь", error: "?" })[modelData[1]]
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: modelData[1] === "good" ? Theme.green : modelData[1] === "bad" ? Theme.peach : Theme.overlay1
                    }
                }
            }
        }
    }

    readonly property var kinds: ({
        choice: choiceComp, toggle: toggleComp, level: levelComp, bands: bandsComp,
        gestures: gesturesComp, devices: devicesComp, ring: ringComp, fitTest: fitComp
    })

    // ===== Раскладка =====

    Column {
        id: col
        anchors.top: parent.top
        anchors.topMargin: 14
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.implicitWidth - 28
        spacing: 10

        // Шапка: Bluetooth · адаптер            [поиск] [вкл]
        Item {
            id: header
            width: parent.width
            height: 34

            Column {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                GradientText {
                    text: "Bluetooth"
                    pixelSize: 15
                }
                Text {
                    visible: Bt.present
                    text: Bt.adapter?.name ?? ""
                    font.family: Theme.font
                    font.pixelSize: 10
                    color: Theme.overlay1
                }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                HeadBtn {
                    visible: Bt.enabled
                    label: "󰑓"
                    on: Bt.scanning
                    anchors.verticalCenter: parent.verticalCenter
                    onPressed: {
                        Bt.scan(!Bt.scanning)
                        root.page = "devices"
                    }
                    RotationAnimator on rotation {
                        running: Bt.scanning
                        loops: Animation.Infinite
                        from: 0; to: 360
                        duration: 1400
                    }
                }
                Md3Switch {
                    visible: Bt.present
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Bt.enabled
                    onToggled: Bt.toggle()
                }
            }
        }

        // ===== Наушники =====
        Rectangle {
            id: budsCard
            visible: root.buds !== null
            width: parent.width
            height: budsCol.implicitHeight + 24
            radius: 16
            color: Theme.cardBg

            Column {
                id: budsCol
                x: 14
                y: 12
                width: parent.width - 28
                spacing: 10

                Item {
                    width: parent.width
                    height: Math.max(nameCol.implicitHeight, retry.height)

                    Column {
                        id: nameCol
                        anchors.left: parent.left
                        anchors.right: retry.left
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: root.buds?.caps?.model ?? root.buds?.name ?? ""
                            font.family: Theme.displayFont
                            font.pixelSize: 22
                            color: Theme.text
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: {
                                switch (root.buds?.status) {
                                case "ready": return root.buds.info?.firmware ? "Прошивка " + root.buds.info.firmware : "На связи"
                                case "connecting": return "Подключаюсь…"
                                default: return root.buds?.message ?? "Нет связи"
                                }
                            }
                            font.family: Theme.font
                            font.pixelSize: 11
                            color: root.buds?.status === "error" ? Theme.red : Theme.overlay1
                        }
                    }
                    TonalBtn {
                        id: retry
                        visible: root.buds?.status === "error"
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Ещё раз"
                        onPressed: Buds.act("reconnect")
                    }
                }

                // Батарея: левый, правый, кейс — волнистые кольца MD3E
                Row {
                    visible: (root.buds?.caps?.battery ?? []).length > 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 18

                    Repeater {
                        model: root.buds?.caps?.battery ?? []

                        Column {
                            id: cell
                            required property string modelData
                            readonly property var b: root.buds?.battery?.[modelData] ?? null
                            spacing: 4

                            WavyRing {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 58
                                height: 58
                                value: (cell.b?.level ?? 0) / 100
                                moving: cell.b?.charging ?? false
                                from: cell.b?.charging ? Theme.green : (cell.b?.level ?? 100) <= 15 ? Theme.red : Theme.gradStart
                                to: cell.b?.charging ? Theme.teal : (cell.b?.level ?? 100) <= 15 ? Theme.maroon : Theme.gradEnd
                                opacity: cell.b ? 1 : 0.4

                                Text {
                                    anchors.centerIn: parent
                                    text: cell.b ? cell.b.level + "" : "—"
                                    font.family: Theme.font
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    color: Theme.text
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: (cell.b?.charging ? "󱐋" : "")
                                    + ({ left: "Левый", right: "Правый", case: "Кейс", single: "Заряд" })[cell.modelData]
                                font.family: Theme.font
                                font.pixelSize: 11
                                color: cell.b?.charging ? Theme.green : Theme.overlay1
                            }
                        }
                    }
                }

                // Несколько поддерживаемых наушников сразу — выбрать какие
                ButtonGroup {
                    visible: Buds.list.length > 1
                    width: parent.width
                    options: Buds.list.map(d => ({ id: d.device, label: d.caps?.model ?? d.name }))
                    current: root.buds?.device
                    onPicked: id => Buds.selected = id
                }
            }
        }

        // ===== Вкладки =====
        // Выбранная — пилюля с подписью, остальные — только значок
        Row {
            id: tabs
            visible: root.pages.length > 1
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4

            Repeater {
                model: root.pages

                Rectangle {
                    id: tabBtn
                    required property string modelData
                    readonly property bool sel: root.tab === modelData
                    readonly property var meta: root.tabMeta[modelData]

                    height: 36
                    width: sel ? tabRow.implicitWidth + 28 : 44
                    Behavior on width { Spring {} }
                    radius: sel ? 18 : 12
                    Behavior on radius { Spring {} }
                    color: sel ? Theme.alpha(Theme.gradEnd, 0.22) : tma.containsMouse ? Theme.cardBg : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    clip: true

                    Row {
                        id: tabRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: tabBtn.meta.icon
                            font.family: Theme.font
                            font.pixelSize: 16
                            color: tabBtn.sel ? Theme.gradEnd : Theme.overlay1
                        }
                        Text {
                            visible: tabBtn.sel
                            text: tabBtn.meta.label
                            font.family: Theme.font
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: Theme.text
                        }
                    }
                    MouseArea {
                        id: tma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.page = tabBtn.modelData
                    }
                }
            }
        }

        // ===== Страница =====
        // Не влезает в попаут — листается, у краёв тянется
        Item {
            width: parent.width
            height: pageFlick.height

            Flickable {
                id: pageFlick
                width: parent.width
                readonly property real maxH: Settings.popoutMaxHeight - 28 - header.height - col.spacing
                    - (budsCard.visible ? budsCard.height + col.spacing : 0)
                    - (tabs.visible ? tabs.height + col.spacing : 0)
                height: Math.min(pageCol.implicitHeight, maxH)
                contentHeight: pageCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: pageCol
                    width: pageFlick.width
                    spacing: 14

                    // Контролы наушников этой вкладки
                    Repeater {
                        model: root.tab === "devices" ? [] : root.controls.filter(c => c.page === root.tab && root.shown(c))

                        Loader {
                            required property var modelData
                            readonly property var ctl: modelData
                            width: pageCol.width
                            sourceComponent: root.kinds[modelData.kind] ?? null
                        }
                    }

                    // Устройства Bluetooth
                    Column {
                        visible: root.tab === "devices"
                        width: parent.width
                        spacing: 2

                        Text {
                            visible: !Bt.present || !Bt.enabled || Bt.devices.length === 0
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            topPadding: 12
                            bottomPadding: 12
                            text: !Bt.present ? "Адаптера нет" : !Bt.enabled ? "Bluetooth выключен"
                                : Bt.scanning ? "Ищу устройства…" : "Устройств нет — нажми поиск"
                            font.family: Theme.font
                            font.pixelSize: 12
                            color: Theme.overlay1
                        }

                        Repeater {
                            model: Bt.enabled ? Bt.devices : []

                            Rectangle {
                                id: dev
                                required property BluetoothDevice modelData
                                readonly property bool busy: modelData.pairing
                                    || modelData.state === BluetoothDeviceState.Connecting
                                    || modelData.state === BluetoothDeviceState.Disconnecting

                                width: parent.width
                                height: 48
                                radius: modelData.connected ? 24 : 12
                                Behavior on radius { Spring {} }
                                color: modelData.connected ? Theme.alpha(Theme.gradEnd, 0.14)
                                     : devHover.hovered ? Theme.cardBg : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }

                                HoverHandler { id: devHover }

                                // Спарилось — подключаем
                                Connections {
                                    target: dev.modelData
                                    function onPairedChanged() {
                                        if (dev.modelData.paired)
                                            dev.modelData.connect()
                                    }
                                }

                                Text {
                                    id: devIcon
                                    x: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Bt.iconOf(dev.modelData)
                                    font.family: Theme.font
                                    font.pixelSize: 18
                                    color: dev.modelData.connected ? Theme.gradEnd : Theme.overlay1
                                }
                                Column {
                                    anchors.left: devIcon.right
                                    anchors.leftMargin: 12
                                    anchors.right: forget.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: dev.modelData.name || dev.modelData.address
                                        font.family: Theme.font
                                        font.pixelSize: 13
                                        color: Theme.text
                                    }
                                    Text {
                                        text: Bt.stateText(dev.modelData)
                                        font.family: Theme.font
                                        font.pixelSize: 10
                                        color: dev.modelData.connected ? Theme.gradEnd : Theme.overlay1
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (!dev.busy) Bt.activate(dev.modelData)
                                }
                                // Забыть: только спаренные и при наведении
                                HeadBtn {
                                    id: forget
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: dev.busy ? "󰔟" : "󰆴"
                                    opacity: dev.busy || devHover.hovered ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    visible: dev.modelData.paired || dev.busy
                                    onPressed: if (!dev.busy) dev.modelData.forget()
                                }
                            }
                        }
                    }
                }
            }

            Overscroll { flick: pageFlick }
        }
    }

    // ===== Снекбар: настройка не применилась =====
    Rectangle {
        id: snack
        property string text: ""
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 28
        height: snackText.implicitHeight + 24
        radius: 14
        color: Theme.surface1
        y: shown ? root.height - height - 14 : root.height + 8
        Behavior on y { Spring {} }
        property bool shown: false
        visible: y < root.height

        Text {
            id: snackText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 14
            wrapMode: Text.WordWrap
            text: "󰀦  " + snack.text
            font.family: Theme.font
            font.pixelSize: 12
            color: Theme.text
        }

        Timer {
            id: snackTimer
            interval: 3500
            onTriggered: snack.shown = false
        }
        Connections {
            target: Buds
            function onFailed(device, id, message) {
                snack.text = message.charAt(0).toUpperCase() + message.slice(1)
                snack.shown = true
                snackTimer.restart()
            }
        }
    }
}
