import Quickshell
import Quickshell.Io
import "./bar"
import "./services"

ShellRoot {
    Bar {}
    ScreenCorners {}
    DesktopWidget {}

    // niri: `qs ipc call launcher toggle`
    IpcHandler {
        target: "launcher"

        function toggle(): void {
            Ui.popoutRequested("launcher")
        }
    }

    // niri: `qs ipc call popout toggle <calendar|system|music|volume|battery>`
    IpcHandler {
        target: "popout"

        function toggle(name: string): void {
            Ui.popoutRequested(name)
        }
    }
}
