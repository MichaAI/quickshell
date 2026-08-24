pragma Singleton
import QtQuick

QtObject {
    readonly property int barHeight: 34
    readonly property int pillHeight: 26
    readonly property int pillRadius: 9
    readonly property int pillPadding: 10
    readonly property int barSpacing: 6

    readonly property int screenRadius: 14   // внутренние углы к краям монитора
    readonly property int popoutRadius: 16
    readonly property int popoutWing: 14     // радиус "крыльев" попаута к бару
    readonly property int popoutMaxHeight: 480
}
