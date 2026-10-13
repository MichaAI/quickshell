import QtQuick
import Quickshell
import Quickshell.Io
import "./bar"
import "./services"

ShellRoot {
    // Приложения поднимаем сразу, чтобы первый лончер не ждал скан .desktop
    Component.onCompleted: Apps.list

    Bar {}
    ScreenCorners {}
    DesktopWidget {}
    NotificationToasts {}

    // niri: `qs ipc call launcher toggle`
    IpcHandler {
        target: "launcher"

        function toggle(): void {
            Ui.popoutRequested("launcher")
        }
    }

    // niri: `qs ipc call popout toggle <calendar|system|music|volume|battery|notifications>`
    IpcHandler {
        target: "popout"

        function toggle(name: string): void {
            Ui.popoutRequested(name)
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
