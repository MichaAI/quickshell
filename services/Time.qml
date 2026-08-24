pragma Singleton
import Quickshell
import QtQuick

Singleton {
    id: root

    readonly property date now: clock.date
    readonly property string time: Qt.formatDateTime(clock.date, "HH:mm:ss")
    readonly property string dateLong: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy")
    readonly property string dayOfWeek: Qt.formatDateTime(clock.date, "dddd")

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }
}
