pragma Singleton
import Quickshell
import QtQuick

// Глобальное UI-состояние шелла.
Singleton {
    property var trayMenuHandle: null

    signal closePopouts()
    signal popoutRequested(string name)
}
