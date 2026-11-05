// Рендер через Vulkan: на той же картинке чуть меньше процессора и
// ~50 МБ памяти, чем GL. Вернуть GL — убрать строку.
//@ pragma Env QSG_RHI_BACKEND=vulkan
// Mailbox вместо FIFO: в FIFO present ждёт frame callback без тайм-аута,
// а поверхности лока после разлочки niri его может не прислать — поток
// рендера встаёт, и шелл виснет на уничтожении окна. Процессора и кадров
// mailbox не добавляет (niri сам отдаёт буферы в такт экрану)
//@ pragma Env MESA_VK_WSI_PRESENT_MODE=mailbox

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
        // Не засыпать ↔ как обычно
        function toggle(): void {
            Idle.toggle()
        }
        // Не засыпать: минуты, -1 — пока не выключат, 0 — выключить
        function awake(minutes: int): void {
            Idle.stayAwake(minutes)
        }
        function status(): string {
            return Idle.status.text
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
