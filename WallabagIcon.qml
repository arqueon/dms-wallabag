// WallabagIcon.qml — wallabag logo tinted to the theme color (light/dark)
// By default uses the stylized "w" (cropped from the official icon, no padding);
// with full:true it shows the whole wallaby (for empty states, etc.).
// Logo: wallabag/logo and wallabag/wallabag (Free Art License 1.3), design by Maylis Agniel

import QtQuick
import QtQuick.Effects
import qs.Common

Item {
    id: root

    // Glyph height; width derives from the real SVG aspect ratio
    property int size: 18
    property bool full: false
    property color iconColor: Theme.surfaceText
    property real iconOpacity: 0.9

    // wallabag-w.svg viewBox: 46.9 × 36.6
    width: full ? size : Math.round(size * 46.9 / 36.6)
    height: size

    Image {
        anchors.fill: parent
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
