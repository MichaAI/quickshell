pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import QtQuick
import "../config"
import "../services"
import "../components"

// Polkit-агент шелла: запрос прав (pkexec, systemctl, монтирование…)
// карточкой в стиле лока поверх затемнённого сфокусированного экрана.
// Поле пароля — то же, что на локе. ⏎ — подтвердить, Esc — отменить.
// Агент один на сессию: пока работает чужой (polkit-kde из niri-flake),
// этот не зарегистрируется и молчит.
Scope {
    id: root

    PolkitAgent {
        id: agent
    }

    LazyLoader {
        active: agent.isActive && agent.flow !== null // qmllint disable unresolved-type

        PanelWindow { // qmllint disable uncreatable-type
            id: win

            readonly property var flow: agent.flow // qmllint disable unresolved-type

            screen: Quickshell.screens.find(s => s.name === Compositor.focusedOutput) ?? Quickshell.screens[0]
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "quickshell:polkit"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            // Состояние для PasswordField — как ctx у лока
            QtObject {
                id: auth
                property string text: ""
                readonly property int length: text.length
                property bool busy: false
                property string error: ""

                function submit() {
                    if (busy || !win.flow || !win.flow.isResponseRequired)
                        return
                    error = ""
                    busy = true
                    win.flow.submit(text)
                }
            }

            Connections {
                target: win.flow
                ignoreUnknownSignals: true

                // Следующий запрос (после ошибки или смены пользователя)
                function onIsResponseRequiredChanged() {
                    if (win.flow.isResponseRequired && auth.busy) {
                        auth.busy = false
                        auth.text = ""
                    }
                }
                function onAuthenticationFailed() {
                    auth.busy = false
                    auth.text = ""
                    auth.error = win.flow.supplementaryIsError && win.flow.supplementaryMessage !== ""
                        ? win.flow.supplementaryMessage : "Неверный пароль"
                }
            }

            // Подсказка PAM («Password: ») — по-русски, если это пароль
            function placeholder() {
                const p = (flow?.inputPrompt ?? "").replace(/[:：]\s*$/, "").trim()
                return p === "" || /^password$/i.test(p) || /^пароль$/i.test(p) ? "Пароль" : p
            }

            function idName(i) {
                return i ? (i.displayName || i.name || "?") : "?"
            }

            // Невидимый ввод: точки рисует PasswordField
            TextInput {
                id: input
                visible: false
                focus: true
                echoMode: win.flow?.responseVisible ? TextInput.Normal : TextInput.Password
                enabled: !auth.busy
                onTextChanged: {
                    if (auth.text !== text) auth.text = text
                    if (text !== "") auth.error = ""
                }
                Keys.onReturnPressed: auth.submit()
                Keys.onEnterPressed: auth.submit()
                Keys.onEscapePressed: win.flow?.cancelAuthenticationRequest()

                Connections {
                    target: auth
                    function onTextChanged() {
                        if (input.text !== auth.text)
                            input.text = auth.text
                    }
                }
            }

            // Затемнение; клик мимо карточки — отмена
            Rectangle {
                id: dim
                anchors.fill: parent
                color: Theme.crust
                opacity: 0
                Component.onCompleted: opacity = 0.6
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                MouseArea {
                    anchors.fill: parent
                    onClicked: win.flow?.cancelAuthenticationRequest()
                }
            }

            Rectangle {
                id: card
                anchors.centerIn: parent
                width: 400
                height: col.implicitHeight + 48
                radius: 28
                color: Theme.popoutBg
                border.width: 1
                border.color: Theme.surface0
                scale: 0.92
                opacity: 0
                Component.onCompleted: { scale = 1; opacity = 1 }
                Behavior on scale { Spring {} }
                Behavior on opacity { NumberAnimation { duration: 150 } }

                // Клики по карточке не отменяют
                MouseArea { anchors.fill: parent }

                Column {
                    id: col
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 24
                    spacing: 14

                    Row {
                        spacing: 12

                        Rectangle {
                            width: 40; height: 40
                            radius: 14
                            color: Theme.alpha(Theme.mauve, 0.18)
                            Text {
                                anchors.centerIn: parent
                                text: "󰒃"
                                font.family: Theme.font
                                font.pixelSize: 20
                                color: Theme.mauve
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            GradientText {
                                pixelSize: 17
                                text: "Нужны права"
                            }
                            Text {
                                text: win.flow?.actionId ?? ""
                                visible: text !== ""
                                font.family: Theme.font
                                font.pixelSize: 10
                                color: Theme.overlay0
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: win.flow?.message ?? ""
                        wrapMode: Text.Wrap
                        font.family: Theme.font
                        font.pixelSize: 13
                        color: Theme.subtext0
                    }

                    // Кем подтверждать — если можно выбрать
                    ChipGroup {
                        width: parent.width
                        visible: (win.flow?.identities.length ?? 0) > 1
                        options: (win.flow?.identities ?? []).map((i, n) => ({ id: String(n), label: win.idName(i) }))
                        current: String((win.flow?.identities ?? []).indexOf(win.flow?.selectedIdentity))
                        onPicked: id => {
                            auth.busy = false
                            auth.error = ""
                            auth.text = ""
                            win.flow.selectedIdentity = win.flow.identities[parseInt(id)]
                        }
                    }

                    // Сообщение PAM, не ошибка (ошибку покажет само поле)
                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: win.flow && !win.flow.supplementaryIsError ? win.flow.supplementaryMessage : ""
                        wrapMode: Text.Wrap
                        font.family: Theme.font
                        font.pixelSize: 11
                        color: Theme.overlay1
                    }

                    PasswordField {
                        width: parent.width
                        height: 50
                        ctx: auth
                        echo: win.flow?.responseVisible ?? false
                        placeholder: win.placeholder()
                        backdrop: Theme.popoutBg
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "⏎ подтвердить   ·   Esc отменить"
                        font.family: Theme.font
                        font.pixelSize: 11
                        color: Theme.overlay0
                    }
                }
            }
        }
    }
}
