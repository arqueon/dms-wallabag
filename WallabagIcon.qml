// WallabagIcon.qml — wallabag logo tinted to the theme color (light/dark)
// By default uses the stylized "w" (cropped from the official icon, no padding);
// with full:true it shows the whole wallaby (for empty states, etc.).
// Logo: wallabag/logo and wallabag/wallabag (Free Art License 1.3), design by Maylis Agniel

import QtQuick
import QtQuick.Effects
import qs.Common

Item {
    id: root

    // Nominal DMS icon box. The drawing is optically scaled inside it so the
    // wide "w" never exceeds neighbouring Material icons.
    property int size: 18
    property bool full: false
    property real opticalScale: full ? 1.0 : 0.72
    property color iconColor: Theme.surfaceText
    property real iconOpacity: 0.9

    width: size
    height: size

    Image {
        // wallabag-w.svg viewBox: 46.9 × 36.6
        width: root.full
               ? Math.round(root.size * root.opticalScale)
               : Math.round(root.size * root.opticalScale * 46.9 / 36.6)
        height: Math.round(root.size * root.opticalScale)
        anchors.centerIn: parent
        source: Qt.resolvedUrl(root.full ? "Images/wallabag.svg" : "Images/wallabag-w.svg")
        sourceSize.width: root.width * 2
        sourceSize.height: root.height * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
        antialiasing: true
        cache: false
        opacity: root.iconOpacity
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            saturation: 0
            colorization: 1
            colorizationColor: root.iconColor
        }
    }
}
