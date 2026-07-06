// WallabagIcon.qml — logo de wallabag tintado al color del tema (claro/oscuro)
// Por defecto usa la «w» estilizada (recortada del icono oficial, sin padding);
// con full:true muestra el ualabí completo (para estados vacíos, etc.).
// Logo: wallabag/logo y wallabag/wallabag (Free Art License 1.3), diseño de Maylis Agniel

import QtQuick
import QtQuick.Effects
import qs.Common

Item {
    id: root

    // Altura del glifo; el ancho se deriva de la proporción real del SVG
    property int size: 18
    property bool full: false
    property color iconColor: Theme.surfaceText
    property real iconOpacity: 0.9

    // viewBox de wallabag-w.svg: 46.9 × 36.6
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
