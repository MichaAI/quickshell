// Рендер через Vulkan: на той же картинке чуть меньше процессора и
// ~50 МБ памяти, чем GL. Вернуть GL — убрать строку.
//@ pragma Env QSG_RHI_BACKEND=vulkan

import QtQuick
import Quickshell
import Quickshell.Io
import "./bar"
import "./services"
import "./lock"

ShellRoot {
    // Приложения поднимаем сразу, чтобы первый лончер не ждал скан .desktop.
    // BtAudio — тоже: запомненное качество LDAC он ставит при подключении
    // наушников, не дожидаясь, пока откроют попаут Bluetooth
    Component.onCompleted: {
        Apps.list
        BtAudio.dev
    }

    Bar {}
    ScreenCorners {}
    DesktopWidget {}
    NotificationToasts {}
    IdleWarning {}
    PolkitDialog {}
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
        target: "idle"
        function toggle(): void {
            Idle.toggle()
        }
        // auto | lock | awake
        function set(mode: string): void {
            Idle.setMode(mode)
        }
        function status(): string {
            return Idle.mode + ": " + Idle.describe()
        }
    }

    // OSD руками: qs ipc call osd trigger volume|mic|brightness
    IpcHandler {
        target: "osd"
        function trigger(kind: string): void {
            Osd.show(kind)
        }
    }

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
