import QtQuick
import Quickshell
import Quickshell.Io
import "./bar"
import "./services"
import "./lock"

ShellRoot {
    // Приложения поднимаем сразу, чтобы первый лончер не ждал скан .desktop
    Component.onCompleted: Apps.list

    Bar {}
    ScreenCorners {}
    DesktopWidget {}
    NotificationToasts {}
    Lock {}

    // niri: `qs ipc call <launcher|calendar|weather|system|music|volume|battery|bluetooth|notifications> <toggle|open|close>`
    Variants {
        model: ["launcher", "calendar", "weather", "system", "music", "volume", "battery", "bluetooth", "notifications"]

        // Обёртка, чтобы modelData не торчал наружу как IPC-свойство
        Scope {
            id: popout
            required property string modelData

            IpcHandler {
                target: popout.modelData

                function toggle(): void {
                    Ui.popoutRequested(popout.modelData)
                }

                function open(): void {
                    Ui.popoutOpenRequested(popout.modelData)
                }

                function close(): void {
                    Ui.popoutCloseRequested(popout.modelData)
                }
            }
        }
    }

    // niri: `qs ipc call popout <toggle|open|close> <calendar|weather|system|music|volume|battery|bluetooth|notifications>`
    IpcHandler {
        target: "popout"

        function toggle(name: string): void {
            Ui.popoutRequested(name)
        }

        function open(name: string): void {
            Ui.popoutOpenRequested(name)
        }

        function close(name: string): void {
            Ui.popoutCloseRequested(name)
        }
    }

    // niri: `qs ipc call notifs <toggleDnd|clear>`
    IpcHandler {
        target: "notifs"

        function toggleDnd(): void {
            Notifs.toggleDnd()
        }

        function clear(): void {
            Notifs.clearAll()
        }
    }
}
