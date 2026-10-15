pragma Singleton
import Quickshell
import QtQuick

// Глобальное UI-состояние шелла.
Singleton {
    property var trayMenuHandle: null
    // Сколько баров (по мониторам) сейчас держат попаут открытым
    property int openPopouts: 0

    signal closePopouts()
    signal popoutRequested(string name)
    // Открыть/закрыть конкретный попаут без переключения (IPC)
    signal popoutOpenRequested(string name)
    signal popoutCloseRequested(string name)
    // Заблокировать экран (lock/Lock.qml). Разблокировки отсюда нет — только паролем
    signal lockRequested()
}
