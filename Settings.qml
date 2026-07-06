// Settings.qml — ajustes del plugin Wallabag
//
// Los datos no sensibles se guardan en plugin_settings.json (StringSetting…).
// El client secret y la contraseña van al llavero del sistema vía secret-tool
// (service=dms-wallabag); aquí solo se escriben, nunca se muestran.

import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root

    pluginId: "wallabag"

    property bool clientSecretStored: false
    property bool passwordStored: false

    function checkSecret(key, cb) {
        Proc.runCommand("wallabag.settings.check." + key,
                        ["secret-tool", "lookup", "service", "dms-wallabag", "key", key],
                        (stdout, exitCode) => cb(exitCode === 0 && String(stdout).trim() !== ""))
    }

    function storeSecret(key, value, cb) {
        var trimmed = String(value || "").trim()
        if (trimmed === "") {
            cb(false)
            return
        }
        var escaped = trimmed.replace(/'/g, "'\\''")
        Proc.runCommand("wallabag.settings.store." + key,
                        ["sh", "-c",
                         "printf %s '" + escaped + "' | secret-tool store --label='DMS Wallabag "
                         + key + "' service dms-wallabag key " + key],
                        (stdout, exitCode) => {
                            var ok = exitCode === 0
                            cb(ok)
                            if (ok)
                                root.saveValue("secretsStamp", String(Date.now()))
                        })
    }

    Component.onCompleted: {
        checkSecret("client_secret", ok => clientSecretStored = ok)
        checkSecret("password", ok => passwordStored = ok)
    }

    StyledText {
        width: parent.width
        text: "Servidor"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StringSetting {
        settingKey: "baseUrl"
        label: "URL de la instancia"
        description: "Raíz de tu Wallabag autoalojado, sin barra final"
        placeholder: "https://wallabag.midominio.org"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "clientId"
        label: "Client ID de la API"
        description: "Créalo en tu Wallabag: menú → API clients management (/developer)"
        placeholder: "1_xxxxxxxxxxxx"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "username"
        label: "Usuario"
        description: "Tu usuario (o email) de Wallabag"
        placeholder: "usuario"
        defaultValue: ""
    }

    StyledText {
        width: parent.width
        text: "Credenciales secretas"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingL
    }

    StyledText {
        width: parent.width
        text: "Se guardan en el llavero del sistema (secret-tool, servicio «dms-wallabag»), nunca en texto plano. Escribe el valor y pulsa Guardar."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // Client secret
    Column {
        width: parent.width
        spacing: Theme.spacingXS

        StyledText {
            text: "Client secret" + (root.clientSecretStored ? "   ✓ guardado en el llavero" : "")
            font.pixelSize: Theme.fontSizeMedium
            color: root.clientSecretStored ? Theme.primary : Theme.surfaceText
        }

        Row {
            width: parent.width
            spacing: Theme.spacingS

            DankTextField {
                id: clientSecretField
                width: parent.width - 100 - Theme.spacingS
                height: 36
                echoMode: TextInput.Password
                placeholderText: "Client secret del cliente API"
            }

            Rectangle {
                width: 100
                height: 36
                radius: Theme.cornerRadius
                color: csArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.35)
                                            : Theme.withAlpha(Theme.primary, 0.22)

                StyledText {
                    anchors.centerIn: parent
                    text: "Guardar"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.primary
                }

                MouseArea {
                    id: csArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.storeSecret("client_secret", clientSecretField.text, ok => {
                        if (ok) {
                            root.clientSecretStored = true
                            clientSecretField.text = ""
                        }
                    })
                }
            }
        }
    }

    // Contraseña
    Column {
        width: parent.width
        spacing: Theme.spacingXS

        StyledText {
            text: "Contraseña de Wallabag" + (root.passwordStored ? "   ✓ guardada en el llavero" : "")
            font.pixelSize: Theme.fontSizeMedium
            color: root.passwordStored ? Theme.primary : Theme.surfaceText
        }

        Row {
            width: parent.width
            spacing: Theme.spacingS

            DankTextField {
                id: passwordField
                width: parent.width - 100 - Theme.spacingS
                height: 36
                echoMode: TextInput.Password
                placeholderText: "Contraseña del usuario"
            }

            Rectangle {
                width: 100
                height: 36
                radius: Theme.cornerRadius
                color: pwArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.35)
                                            : Theme.withAlpha(Theme.primary, 0.22)

                StyledText {
                    anchors.centerIn: parent
                    text: "Guardar"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.primary
                }

                MouseArea {
                    id: pwArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.storeSecret("password", passwordField.text, ok => {
                        if (ok) {
                            root.passwordStored = true
                            passwordField.text = ""
                        }
                    })
                }
            }
        }
    }

    StyledText {
        width: parent.width
        text: "Comportamiento"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingL
    }

    SelectionSetting {
        settingKey: "pollInterval"
        label: "Intervalo de sondeo"
        description: "Cada cuánto se actualiza el contador de no leídas"
        options: [
            { label: "5 min", value: "300" },
            { label: "15 min", value: "900" },
            { label: "30 min", value: "1800" },
            { label: "1 h", value: "3600" }
        ]
        defaultValue: "900"
    }

    SelectionSetting {
        settingKey: "perPage"
        label: "Entradas por página"
        options: [
            { label: "20", value: "20" },
            { label: "30", value: "30" },
            { label: "50", value: "50" }
        ]
        defaultValue: "30"
    }

    ToggleSetting {
        settingKey: "archiveOnOpen"
        label: "Archivar al abrir"
        description: "Marca la entrada como leída al abrirla en el navegador"
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "showThumbnails"
        label: "Miniaturas"
        description: "Muestra la imagen de vista previa de cada entrada"
        defaultValue: true
    }
}
