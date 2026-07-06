// Settings.qml — settings UI for the Wallabag plugin
//
// Non-sensitive values are stored in plugin_settings.json (StringSetting…).
// The client secret and the password go to the system keyring via secret-tool
// (service=dms-wallabag); they are only written here, never displayed.

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
        text: "Server"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StringSetting {
        settingKey: "baseUrl"
        label: "Instance URL"
        description: "Root of your self-hosted Wallabag, without trailing slash"
        placeholder: "https://wallabag.example.org"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "clientId"
        label: "API client ID"
        description: "Create it in your Wallabag: menu → API clients management (/developer)"
        placeholder: "1_xxxxxxxxxxxx"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "username"
        label: "Username"
        description: "Your Wallabag username (or email)"
        placeholder: "user"
        defaultValue: ""
    }

    StyledText {
        width: parent.width
        text: "Secret credentials"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingL
    }

    StyledText {
        width: parent.width
        text: "Stored in the system keyring (secret-tool, service “dms-wallabag”), never in plain text. Type the value and press Save."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // Client secret
    Column {
        width: parent.width
        spacing: Theme.spacingXS

        StyledText {
            text: "Client secret" + (root.clientSecretStored ? "   ✓ stored in keyring" : "")
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
                placeholderText: "Client secret of the API client"
            }

            Rectangle {
                width: 100
                height: 36
                radius: Theme.cornerRadius
                color: csArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.35)
                                            : Theme.withAlpha(Theme.primary, 0.22)

                StyledText {
                    anchors.centerIn: parent
                    text: "Save"
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

    // Password
    Column {
        width: parent.width
        spacing: Theme.spacingXS

        StyledText {
            text: "Wallabag password" + (root.passwordStored ? "   ✓ stored in keyring" : "")
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
                placeholderText: "Password of the user"
            }

            Rectangle {
                width: 100
                height: 36
                radius: Theme.cornerRadius
                color: pwArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.35)
                                            : Theme.withAlpha(Theme.primary, 0.22)

                StyledText {
                    anchors.centerIn: parent
                    text: "Save"
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
        text: "Behavior"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingL
    }

    SelectionSetting {
        settingKey: "pollInterval"
        label: "Poll interval"
        description: "How often the unread counter refreshes"
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
        label: "Entries per page"
        options: [
            { label: "20", value: "20" },
            { label: "30", value: "30" },
            { label: "50", value: "50" }
        ]
        defaultValue: "30"
    }

    ToggleSetting {
        settingKey: "archiveOnOpen"
        label: "Archive on open"
        description: "Mark the entry as read when opening it in the browser"
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "showThumbnails"
        label: "Thumbnails"
        description: "Show each entry's preview picture"
        defaultValue: true
    }
}
