// WallabagWidget.qml — DMS bar widget for Wallabag
//
// Pill with the wallabag logo + unread counter; popout with the entry list
// (source, excerpt, links that do not close the window) and per-row actions:
// archive/read, star, delete, re-fetch, copy URL. Multi-select batch actions.
// API: OAuth2 password grant + refresh against the configured instance.

import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Services
import qs.Modules.Plugins
import "./JS/wallabag.js" as WB

PluginComponent {
    id: root

    property var popoutService: null

    // ── Settings (pluginData is reactive) ──────────────────────────────────
    property string baseUrl: String(pluginData.baseUrl || "").trim().replace(/\/+$/, "")
    property string clientId: String(pluginData.clientId || "").trim()
    property string username: String(pluginData.username || "").trim()
    property int pollIntervalMs: (parseInt(pluginData.pollInterval) || 900) * 1000
    property int perPage: parseInt(pluginData.perPage) || 30
    property bool archiveOnOpen: pluginData.archiveOnOpen === true
    property bool showThumbnails: pluginData.showThumbnails !== false
    property bool hideWhenZero: pluginData.hideWhenZero === true
    readonly property bool pillHidden: hideWhenZero && configured && unreadTotal === 0
    property string secretsStamp: String(pluginData.secretsStamp || "")

    // ── Secrets (system keyring via secret-tool) ────────────────────
    property string clientSecret: ""
    property string password: ""
    property bool secretsLoaded: false

    readonly property bool configured: baseUrl !== "" && clientId !== ""
                                       && username !== "" && clientSecret !== ""
                                       && password !== ""

    // ── OAuth ─────────────────────────────────────────────────────────────
    property string accessToken: ""
    property string refreshToken: ""
    property double tokenExpiresAt: 0

    // ── Data ─────────────────────────────────────────────────────────────
    property var entries: []
    property int unreadTotal: 0
    property string filter: String(pluginData.filter || "unread")
    property string searchTerm: ""
    property string pendingSearch: ""
    property int page: 1
    property int pages: 1
    property int totalCount: 0
    property bool isLoading: false
    property string errorMessage: ""
    property int expandedId: -1
    property var contentCache: ({})
    property int pendingDeleteId: -1
    property double lastUpdated: 0
    property int _reqSeq: 0

    readonly property var filterOptions: [
        { label: "Unread", value: "unread" },
        { label: "Starred", value: "starred" },
        { label: "Archive", value: "archive" },
        { label: "All", value: "all" }
    ]

    readonly property string headerDetails: {
        if (!secretsLoaded)
            return "Reading credentials from the keyring…"
        if (!configured)
            return "Configure the connection in Settings → Plugins → Wallabag"
        if (errorMessage !== "")
            return errorMessage
        if (isLoading && entries.length === 0)
            return "Loading entries…"
        var detail = unreadTotal + " unread"
        if (searchTerm !== "")
            detail += " · search: " + totalCount + " results"
        else if (filter !== "unread")
            detail += " · " + totalCount + " in this view"
        return detail
    }

    // ── Secrets ──────────────────────────────────────────────────────────

    function _lookupSecret(key, cb) {
        Proc.runCommand("wallabag.lookup." + key + "." + (++_reqSeq),
                        ["secret-tool", "lookup", "service", "dms-wallabag", "key", key],
                        (stdout, exitCode) => {
                            cb(exitCode === 0 ? String(stdout).trim() : "")
                        })
    }

    function loadSecrets(then) {
        _lookupSecret("client_secret", s => {
            clientSecret = s
            _lookupSecret("password", p => {
                password = p
                secretsLoaded = true
                if (then)
                    then()
            })
        })
    }

    // ── OAuth ─────────────────────────────────────────────────────────────

    function _tokenRequest(fields, cb) {
        var argv = ["curl", "-sS", "--max-time", "20", "-w", "\n%{http_code}",
                    "-X", "POST", baseUrl + "/oauth/v2/token"]
        for (var key in fields) {
            argv.push("--data-urlencode")
            argv.push(key + "=" + fields[key])
        }
        Proc.runCommand("wallabag.token." + (++_reqSeq), argv, (stdout, exitCode) => {
            var res = WB.parseCurl(stdout, exitCode)
            if (res.status === 200 && res.json && res.json.access_token) {
                accessToken = res.json.access_token
                refreshToken = res.json.refresh_token || ""
                var lifetime = Math.max(60, (res.json.expires_in || 3600) - 60)
                tokenExpiresAt = Date.now() + lifetime * 1000
                cb(true)
            } else {
                cb(false, WB.errorText(res))
            }
        })
    }

    function ensureToken(cb) {
        if (accessToken !== "" && Date.now() < tokenExpiresAt) {
            cb(true)
            return
        }
        var passwordGrant = () => _tokenRequest({
            grant_type: "password",
            client_id: clientId,
            client_secret: clientSecret,
            username: username,
            password: password
        }, cb)
        if (refreshToken !== "") {
            _tokenRequest({
                grant_type: "refresh_token",
                refresh_token: refreshToken,
                client_id: clientId,
                client_secret: clientSecret
            }, ok => ok ? cb(true) : passwordGrant())
        } else {
            passwordGrant()
        }
    }

    // ── HTTP client (curl via Proc) ──────────────────────────────────────

    function apiCall(method, path, query, form, cb) {
        if (!configured) {
            cb({ status: 0, json: null, error: "not configured" })
            return
        }
        var attempt = retriesLeft => {
            ensureToken((ok, err) => {
                if (!ok) {
                    cb({ status: 401, json: null, error: err || "authentication failed" })
                    return
                }
                var url = baseUrl + path
                var queryStr = query ? WB.buildQuery(query) : ""
                if (queryStr !== "")
                    url += "?" + queryStr
                var argv = ["curl", "-sS", "--max-time", "30", "-w", "\n%{http_code}",
                            "-X", method, "-H", "Authorization: Bearer " + accessToken, url]
                if (form) {
                    for (var key in form) {
                        argv.push("--data-urlencode")
                        argv.push(key + "=" + form[key])
                    }
                }
                Proc.runCommand("wallabag.api." + (++_reqSeq), argv, (stdout, exitCode) => {
                    var res = WB.parseCurl(stdout, exitCode)
                    if (res.status === 401 && retriesLeft > 0) {
                        accessToken = ""
                        attempt(retriesLeft - 1)
                        return
                    }
                    cb(res)
                })
            })
        }
        attempt(1)
    }

    // ── Fetching entries ───────────────────────────────────────────────

    function matchesFilter(entry) {
        if (searchTerm !== "")
            return true
        if (filter === "unread") return !entry.isArchived
        if (filter === "starred") return entry.isStarred
        if (filter === "archive") return entry.isArchived
        return true
    }

    function fetchEntries(reset) {
        if (!configured)
            return
        if (reset)
            page = 1
        isLoading = true
        var requestedPage = page
        var done = res => {
            isLoading = false
            if (res.status !== 200 || !res.json) {
                errorMessage = "Error: " + WB.errorText(res)
                return
            }
            errorMessage = ""
            var items = (res.json._embedded && res.json._embedded.items) || []
            var mapped = WB.mapEntries(items)
            entries = requestedPage === 1 ? mapped : entries.concat(mapped)
            pages = res.json.pages || 1
            totalCount = res.json.total !== undefined ? res.json.total : mapped.length
            lastUpdated = Date.now()
            _pruneSelection()
            if (searchTerm === "" && filter === "unread") {
                unreadTotal = totalCount
                pluginService?.savePluginState(pluginId, "unreadTotal", unreadTotal)
            }
        }
        if (searchTerm !== "") {
            apiCall("GET", "/api/search.json",
                    { term: searchTerm, page: requestedPage, perPage: perPage }, null, done)
        } else {
            var query = { page: requestedPage, perPage: perPage, detail: "metadata",
                          sort: "created", order: "desc" }
            if (filter === "unread") query.archive = 0
            else if (filter === "starred") query.starred = 1
            else if (filter === "archive") query.archive = 1
            apiCall("GET", "/api/entries.json", query, null, done)
        }
    }

    function loadMore() {
        if (isLoading || page >= pages)
            return
        page += 1
        fetchEntries(false)
    }

    function refreshUnread() {
        if (!configured)
            return
        apiCall("GET", "/api/entries.json",
                { archive: 0, perPage: 1, detail: "metadata" }, null, res => {
            if (res.status === 200 && res.json && res.json.total !== undefined) {
                unreadTotal = res.json.total
                errorMessage = ""
                pluginService?.savePluginState(pluginId, "unreadTotal", unreadTotal)
            } else if (entries.length === 0) {
                errorMessage = "Error: " + WB.errorText(res)
            }
        })
    }

    function refreshAll() {
        refreshUnread()
        fetchEntries(true)
    }

    function setFilter(value) {
        if (filter === value)
            return
        filter = value
        pluginService?.savePluginData(pluginId, "filter", value)
        expandedId = -1
        fetchEntries(true)
    }

    function setSearchTerm(term) {
        var trimmed = String(term || "").trim()
        if (searchTerm === trimmed)
            return
        searchTerm = trimmed
        expandedId = -1
        fetchEntries(true)
    }

    // ── Entry actions ───────────────────────────────────────────

    function _replaceEntry(id, mapped, keep) {
        var next = []
        for (var i = 0; i < entries.length; i++) {
            if (entries[i].id === id) {
                if (keep)
                    next.push(mapped)
            } else {
                next.push(entries[i])
            }
        }
        entries = next
        if (!keep) {
            totalCount = Math.max(0, totalCount - 1)
            if (expandedId === id)
                expandedId = -1
        }
    }

    function _applyServerEntry(json) {
        if (!json || json.id === undefined)
            return
        var mapped = WB.mapEntry(json)
        _replaceEntry(mapped.id, mapped, matchesFilter(mapped))
    }

    function _patchEntry(entry, form, localPatch) {
        var previous = entries
        entries = entries.map(e => e.id === entry.id ? Object.assign({}, e, localPatch) : e)
        apiCall("PATCH", "/api/entries/" + entry.id + ".json", null, form, res => {
            if (res.status === 200 && res.json) {
                _applyServerEntry(res.json)
            } else {
                entries = previous
                ToastService?.showError("Wallabag: " + WB.errorText(res))
            }
        })
    }

    function toggleStar(entry) {
        _patchEntry(entry, { starred: entry.isStarred ? 0 : 1 },
                    { isStarred: !entry.isStarred })
    }

    function toggleArchive(entry) {
        var willArchive = !entry.isArchived
        unreadTotal = Math.max(0, unreadTotal + (willArchive ? -1 : 1))
        pluginService?.savePluginState(pluginId, "unreadTotal", unreadTotal)
        _patchEntry(entry, { archive: willArchive ? 1 : 0 },
                    { isArchived: willArchive })
    }

    function requestDelete(entry) {
        if (pendingDeleteId !== entry.id) {
            pendingDeleteId = entry.id
            deleteConfirmTimer.restart()
            return
        }
        deleteConfirmTimer.stop()
        pendingDeleteId = -1
        apiCall("DELETE", "/api/entries/" + entry.id + ".json",
                { expect: "id" }, null, res => {
            if (res.status === 200) {
                if (!entry.isArchived) {
                    unreadTotal = Math.max(0, unreadTotal - 1)
                    pluginService?.savePluginState(pluginId, "unreadTotal", unreadTotal)
                }
                _replaceEntry(entry.id, null, false)
            } else {
                ToastService?.showError("Wallabag: could not delete — " + WB.errorText(res))
            }
        })
    }

    function reloadEntry(entry) {
        apiCall("PATCH", "/api/entries/" + entry.id + "/reload.json", null, null, res => {
            if (res.status === 200 && res.json) {
                _applyServerEntry(res.json)
                var cache = Object.assign({}, contentCache)
                delete cache[entry.id]
                contentCache = cache
                if (expandedId === entry.id)
                    fetchExcerpt(entry.id)
                ToastService?.showInfo("Content re-fetched")
            } else if (res.status === 304) {
                ToastService?.showInfo("wallabag could not re-fetch the content")
            } else {
                ToastService?.showError("Wallabag: " + WB.errorText(res))
            }
        })
    }

    function openEntry(entry) {
        if (!entry.url)
            return
        Quickshell.execDetached(["xdg-open", entry.url])
        if (archiveOnOpen && !entry.isArchived)
            toggleArchive(entry)
    }

    function copyUrl(entry) {
        Quickshell.execDetached(["dms", "cl", "copy", entry.url])
        ToastService?.showInfo("URL copied")
    }

    function addUrl(url) {
        var trimmed = String(url || "").trim()
        if (trimmed === "")
            return
        apiCall("POST", "/api/entries.json", null, { url: trimmed }, res => {
            if (res.status === 200) {
                ToastService?.showInfo("Saved to Wallabag")
                refreshAll()
            } else {
                ToastService?.showError("Wallabag: could not save — " + WB.errorText(res))
            }
        })
    }

    // ── Multi-select and batch operations ─────────────────────────

    property var selectedIds: ({})
    readonly property int selectedCount: Object.keys(selectedIds).length
    property bool batchDeleteArmed: false

    // Sequential queue: batches fire one request at a time
    property var _opQueue: []
    property bool _opRunning: false

    function _enqueueOps(fns) {
        _opQueue = _opQueue.concat(fns)
        _pumpOps()
    }

    function _pumpOps() {
        if (_opRunning || _opQueue.length === 0)
            return
        _opRunning = true
        var fn = _opQueue[0]
        _opQueue = _opQueue.slice(1)
        fn(() => {
            _opRunning = false
            _pumpOps()
        })
    }

    function isSelected(id) {
        return selectedIds[id] === true
    }

    function toggleSelect(id) {
        var next = Object.assign({}, selectedIds)
        if (next[id])
            delete next[id]
        else
            next[id] = true
        selectedIds = next
        if (selectedCount === 0)
            batchDeleteArmed = false
    }

    function selectAllVisible() {
        var next = {}
        for (var i = 0; i < entries.length; i++)
            next[entries[i].id] = true
        selectedIds = next
    }

    function clearSelection() {
        selectedIds = ({})
        batchDeleteArmed = false
    }

    function _pruneSelection() {
        var next = {}
        for (var i = 0; i < entries.length; i++) {
            if (selectedIds[entries[i].id])
                next[entries[i].id] = true
        }
        if (Object.keys(next).length !== selectedCount)
            selectedIds = next
    }

    function _selectedEntries() {
        return entries.filter(e => selectedIds[e.id] === true)
    }

    function _finishBatch() {
        clearSelection()
        refreshUnread()
    }

    function batchOpen() {
        var targets = _selectedEntries()
        for (var i = 0; i < targets.length; i++)
            openEntry(targets[i])
    }

    function batchArchive() {
        var toArchive = filter !== "archive"
        var targets = _selectedEntries().filter(e => e.isArchived !== toArchive)
        if (targets.length === 0) {
            _finishBatch()
            return
        }
        _enqueueOps(targets.map(e => done => {
            apiCall("PATCH", "/api/entries/" + e.id + ".json", null,
                    { archive: toArchive ? 1 : 0 }, res => {
                if (res.status === 200 && res.json)
                    _applyServerEntry(res.json)
                done()
            })
        }).concat([done => {
            _finishBatch()
            done()
        }]))
    }

    function batchStar() {
        var selected = _selectedEntries()
        if (selected.length === 0)
            return
        // if all are already starred → unstar; otherwise → star all
        var makeStarred = !selected.every(e => e.isStarred)
        var targets = selected.filter(e => e.isStarred !== makeStarred)
        if (targets.length === 0) {
            _finishBatch()
            return
        }
        _enqueueOps(targets.map(e => done => {
            apiCall("PATCH", "/api/entries/" + e.id + ".json", null,
                    { starred: makeStarred ? 1 : 0 }, res => {
                if (res.status === 200 && res.json)
                    _applyServerEntry(res.json)
                done()
            })
        }).concat([done => {
            _finishBatch()
            done()
        }]))
    }

    function batchDelete() {
        if (!batchDeleteArmed) {
            batchDeleteArmed = true
            batchDeleteTimer.restart()
            return
        }
        batchDeleteTimer.stop()
        batchDeleteArmed = false
        var targets = _selectedEntries()
        _enqueueOps(targets.map(e => done => {
            apiCall("DELETE", "/api/entries/" + e.id + ".json",
                    { expect: "id" }, null, res => {
                if (res.status === 200)
                    _replaceEntry(e.id, null, false)
                else
                    ToastService?.showError("Wallabag: could not delete \u201C" + e.title + "\u201D")
                done()
            })
        }).concat([done => {
            _finishBatch()
            done()
        }]))
    }

    // ── Content excerpt (on demand, cached) ────────────────────

    function toggleExpand(entry) {
        if (expandedId === entry.id) {
            expandedId = -1
            return
        }
        expandedId = entry.id
        if (contentCache[entry.id] === undefined)
            fetchExcerpt(entry.id)
    }

    function fetchExcerpt(id) {
        apiCall("GET", "/api/entries/" + id + ".json", null, null, res => {
            var cache = Object.assign({}, contentCache)
            if (res.status === 200 && res.json) {
                var text = WB.excerpt(res.json.content, 480)
                cache[id] = text !== "" ? text : "(no extracted content)"
            } else {
                cache[id] = "(could not load the excerpt)"
            }
            contentCache = cache
        })
    }

    // ── Timers and startup ─────────────────────────────────────────

    Timer {
        id: pollTimer
        interval: root.pollIntervalMs
        running: root.configured
        repeat: true
        onTriggered: root.refreshUnread()
    }

    Timer {
        id: deleteConfirmTimer
        interval: 3500
        onTriggered: root.pendingDeleteId = -1
    }

    Timer {
        id: batchDeleteTimer
        interval: 3500
        onTriggered: root.batchDeleteArmed = false
    }

    Timer {
        id: searchDebounce
        interval: 450
        onTriggered: root.setSearchTerm(root.pendingSearch)
    }

    Component.onCompleted: {
        if (pluginService)
            unreadTotal = pluginService.loadPluginState(pluginId, "unreadTotal", 0)
        loadSecrets(() => {
            if (configured)
                refreshAll()
        })
    }

    onSecretsStampChanged: {
        if (!secretsLoaded)
            return
        loadSecrets(() => {
            accessToken = ""
            refreshToken = ""
            if (configured)
                refreshAll()
        })
    }

    // ── Bar pills ──────────────────────────────────────────────

    horizontalBarPill: Component {
        Item {
            implicitWidth: root.pillHidden ? 0 : pillRow.implicitWidth
            implicitHeight: pillRow.implicitHeight
            visible: !root.pillHidden

            Row {
                id: pillRow
                spacing: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter

                WallabagIcon {
                    size: Math.max(15, root.iconSize - 2)
                    iconColor: {
                        if (!root.configured)
                            return Theme.surfaceVariantText
                        return root.unreadTotal > 0 ? Theme.primary : Theme.surfaceText
                    }
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Unread badge: a proper pill, vertically centered with the icon
                Rectangle {
                    visible: root.unreadTotal > 0
                    width: Math.max(hBadgeText.implicitWidth + 10, height)
                    height: 16
                    radius: height / 2
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter

                    StyledText {
                        id: hBadgeText
                        anchors.centerIn: parent
                        text: WB.formatCount(root.unreadTotal)
                        font.pixelSize: Math.max(9, Math.round(Theme.fontSizeSmall * 0.8))
                        font.weight: Font.Bold
                        color: Theme.primaryText
                    }
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: pillColumn.implicitWidth
            implicitHeight: root.pillHidden ? 0 : pillColumn.implicitHeight
            visible: !root.pillHidden

            Column {
                id: pillColumn
                spacing: Theme.spacingXS

                WallabagIcon {
                    size: Math.max(15, root.iconSize - 2)
                    iconColor: {
                        if (!root.configured)
                            return Theme.surfaceVariantText
                        return root.unreadTotal > 0 ? Theme.primary : Theme.surfaceText
                    }
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Rectangle {
                    visible: root.unreadTotal > 0
                    width: Math.max(vBadgeText.implicitWidth + 10, height)
                    height: 16
                    radius: height / 2
                    color: Theme.primary
                    anchors.horizontalCenter: parent.horizontalCenter

                    StyledText {
                        id: vBadgeText
                        anchors.centerIn: parent
                        text: WB.formatCount(root.unreadTotal)
                        font.pixelSize: Math.max(9, Math.round(Theme.fontSizeSmall * 0.8))
                        font.weight: Font.Bold
                        color: Theme.primaryText
                    }
                }
            }
        }
    }

    pillRightClickAction: () => root.refreshAll()

    // ── Popout ────────────────────────────────────────────────────────────

    popoutWidth: 480
    popoutHeight: 600

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "Wallabag"
            detailsText: root.headerDetails
            showCloseButton: true

            property bool addMode: false

            Component.onCompleted: {
                if (root.configured && Date.now() - root.lastUpdated > 60000)
                    root.fetchEntries(true)
            }

            Component.onDestruction: root.clearSelection()

            // Toolbar: filters + refresh + add
            Item {
                id: toolbar
                width: parent.width
                height: 30

                Rectangle {
                    id: filterControl
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    width: filterRow.implicitWidth + 2
                    height: 26
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Row {
                        id: filterRow
                        anchors.centerIn: parent
                        spacing: 1

                        Repeater {
                            model: root.filterOptions

                            delegate: Rectangle {
                                required property var modelData
                                width: segmentLabel.implicitWidth + Theme.spacingM
                                height: 24
                                radius: Theme.cornerRadius
                                color: root.filter === modelData.value && root.searchTerm === ""
                                       ? Theme.withAlpha(Theme.primary, 0.25)
                                       : "transparent"

                                StyledText {
                                    id: segmentLabel
                                    anchors.centerIn: parent
                                    text: parent.modelData.label
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: root.filter === parent.modelData.value ? Font.DemiBold : Font.Normal
                                    color: root.filter === parent.modelData.value && root.searchTerm === ""
                                           ? Theme.primary : Theme.surfaceVariantText
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setFilter(parent.modelData.value)
                                }
                            }
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS

                    DankActionButton {
                        iconName: "add"
                        buttonSize: 28
                        iconColor: popout.addMode ? Theme.primary : Theme.surfaceVariantText
                        onClicked: popout.addMode = !popout.addMode
                    }

                    DankActionButton {
                        iconName: "refresh"
                        buttonSize: 28
                        iconColor: root.isLoading ? Theme.primary : Theme.surfaceVariantText
                        onClicked: root.refreshAll()
                    }
                }
            }

            // Row to add a new URL
            Item {
                id: addRow
                width: parent.width
                height: popout.addMode ? 36 : 0
                visible: popout.addMode
                clip: true

                DankTextField {
                    id: addField
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    anchors.right: addButton.left
                    anchors.rightMargin: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    height: 32
                    placeholderText: "https://… (save to Wallabag)"
                    onAccepted: {
                        root.addUrl(text)
                        text = ""
                        popout.addMode = false
                    }
                }

                Rectangle {
                    id: addButton
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    width: saveLabel.implicitWidth + Theme.spacingM * 2
                    height: 30
                    radius: Theme.cornerRadius
                    color: saveArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.35)
                                                  : Theme.withAlpha(Theme.primary, 0.22)

                    StyledText {
                        id: saveLabel
                        anchors.centerIn: parent
                        text: "Save"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        color: Theme.primary
                    }

                    MouseArea {
                        id: saveArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.addUrl(addField.text)
                            addField.text = ""
                            popout.addMode = false
                        }
                    }
                }
            }

            // Search
            Item {
                id: searchRow
                width: parent.width
                height: 36

                DankTextField {
                    id: searchField
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    anchors.right: clearSearch.visible ? clearSearch.left : parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    height: 32
                    placeholderText: "Search Wallabag…"
                    text: root.searchTerm
                    onTextEdited: {
                        root.pendingSearch = text
                        searchDebounce.restart()
                    }
                    onAccepted: {
                        searchDebounce.stop()
                        root.setSearchTerm(text)
                    }
                }

                DankActionButton {
                    id: clearSearch
                    visible: searchField.text !== ""
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "close"
                    buttonSize: 28
                    iconColor: Theme.surfaceVariantText
                    onClicked: {
                        searchField.text = ""
                        searchDebounce.stop()
                        root.setSearchTerm("")
                    }
                }
            }

            // Multi-select bar (visible when rows are checked)
            Item {
                id: selectionRow
                width: parent.width
                height: root.selectedCount > 0 ? 34 : 0
                visible: root.selectedCount > 0
                clip: true

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingS
                    anchors.rightMargin: Theme.spacingS
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.primary, 0.12)

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS

                        StyledText {
                            text: root.selectedCount + " selected"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        DankActionButton {
                            iconName: "select_all"
                            buttonSize: 26
                            iconColor: Theme.surfaceVariantText
                            tooltipText: "Select all"
                            onClicked: root.selectAllVisible()
                        }

                        DankActionButton {
                            iconName: "close"
                            buttonSize: 26
                            iconColor: Theme.surfaceVariantText
                            tooltipText: "Clear selection"
                            onClicked: root.clearSelection()
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingXS
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        DankActionButton {
                            iconName: "open_in_new"
                            buttonSize: 26
                            iconColor: Theme.surfaceVariantText
                            tooltipText: "Open all in the browser"
                            onClicked: root.batchOpen()
                        }

                        DankActionButton {
                            iconName: root.filter === "archive" ? "unarchive" : "check_circle"
                            buttonSize: 26
                            iconColor: Theme.surfaceVariantText
                            tooltipText: root.filter === "archive" ? "Unarchive selected" : "Archive (mark read) selected"
                            onClicked: root.batchArchive()
                        }

                        DankActionButton {
                            iconName: "star"
                            buttonSize: 26
                            iconColor: Theme.surfaceVariantText
                            tooltipText: "Star / unstar all selected"
                            onClicked: root.batchStar()
                        }

                        DankActionButton {
                            iconName: root.batchDeleteArmed ? "delete_forever" : "delete"
                            buttonSize: 26
                            iconColor: root.batchDeleteArmed ? Theme.error : Theme.surfaceVariantText
                            tooltipText: root.batchDeleteArmed
                                         ? "Click again: delete " + root.selectedCount + " entries"
                                         : "Delete selected"
                            onClicked: root.batchDelete()
                        }
                    }
                }
            }

            // Entry list
            Item {
                id: listContainer
                width: parent.width
                height: Math.max(120, root.popoutHeight - popout.headerHeight - popout.detailsHeight
                                 - toolbar.height - addRow.height - searchRow.height
                                 - selectionRow.height - Theme.spacingL * 3)

                DankListView {
                    id: entryList
                    anchors.fill: parent
                    clip: true
                    spacing: Theme.spacingXS
                    model: root.entries

                delegate: Rectangle {
                    id: entryRow

                    required property var modelData
                    required property int index

                    readonly property bool expanded: root.expandedId === modelData.id

                    width: entryList.width
                    height: rowContent.implicitHeight + Theme.spacingS * 2
                    radius: Theme.cornerRadius
                    color: rowHover.hovered ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                    HoverHandler { id: rowHover }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.MiddleButton)
                                root.openEntry(entryRow.modelData)
                            else if (root.selectedCount > 0)
                                root.toggleSelect(entryRow.modelData.id)
                            else
                                root.toggleExpand(entryRow.modelData)
                        }
                    }

                    Column {
                        id: rowContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingS
                        spacing: Theme.spacingXS

                        Row {
                            width: parent.width
                            spacing: Theme.spacingS

                            Item {
                                id: checkBox
                                width: 20
                                height: 44
                                anchors.verticalCenter: parent.verticalCenter

                                DankIcon {
                                    anchors.centerIn: parent
                                    name: root.isSelected(entryRow.modelData.id)
                                          ? "check_box" : "check_box_outline_blank"
                                    size: 18
                                    color: root.isSelected(entryRow.modelData.id)
                                           ? Theme.primary : Theme.surfaceVariantText
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleSelect(entryRow.modelData.id)
                                }
                            }

                            Rectangle {
                                id: thumb
                                visible: root.showThumbnails && entryRow.modelData.previewPicture !== ""
                                width: visible ? 44 : 0
                                height: 44
                                radius: Theme.cornerRadius / 2
                                color: Theme.surfaceContainerHighest
                                clip: true
                                anchors.verticalCenter: parent.verticalCenter

                                CachingImage {
                                    anchors.fill: parent
                                    imagePath: entryRow.modelData.previewPicture
                                }
                            }

                            Column {
                                width: parent.width - checkBox.width - Theme.spacingS
                                       - (thumb.visible ? thumb.width + Theme.spacingS : 0)
                                       - actionsColumn.width - Theme.spacingS
                                spacing: 2
                                anchors.verticalCenter: parent.verticalCenter

                                StyledText {
                                    id: titleText
                                    width: parent.width
                                    text: entryRow.modelData.title
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Medium
                                    font.underline: titleArea.containsMouse
                                    color: titleArea.containsMouse ? Theme.primary : Theme.surfaceText
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight

                                    MouseArea {
                                        id: titleArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        // Opens in the browser WITHOUT closing the popout
                                        onClicked: root.openEntry(entryRow.modelData)
                                    }
                                }

                                StyledText {
                                    width: parent.width
                                    text: {
                                        var parts = []
                                        if (entryRow.modelData.domain !== "")
                                            parts.push(entryRow.modelData.domain)
                                        if (entryRow.modelData.readingTime > 0)
                                            parts.push(entryRow.modelData.readingTime + " min")
                                        var when = WB.relativeTime(entryRow.modelData.createdAt)
                                        if (when !== "")
                                            parts.push(when)
                                        return parts.join(" · ")
                                    }
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }

                            Column {
                                id: actionsColumn
                                width: actionButtons.implicitWidth
                                anchors.verticalCenter: parent.verticalCenter

                                Row {
                                    id: actionButtons
                                    spacing: 0

                                    DankActionButton {
                                        iconName: "star"
                                        buttonSize: 28
                                        iconColor: entryRow.modelData.isStarred ? Theme.primary : Theme.surfaceVariantText
                                        onClicked: root.toggleStar(entryRow.modelData)
                                    }

                                    DankActionButton {
                                        iconName: entryRow.modelData.isArchived ? "unarchive" : "check_circle"
                                        buttonSize: 28
                                        iconColor: entryRow.modelData.isArchived ? Theme.primary : Theme.surfaceVariantText
                                        onClicked: root.toggleArchive(entryRow.modelData)
                                    }

                                    DankActionButton {
                                        iconName: "open_in_new"
                                        buttonSize: 28
                                        iconColor: Theme.surfaceVariantText
                                        onClicked: root.openEntry(entryRow.modelData)
                                    }
                                }
                            }
                        }

                        // Expanded detail: excerpt + tags + secondary actions
                        Column {
                            width: parent.width
                            visible: entryRow.expanded
                            spacing: Theme.spacingXS

                            StyledText {
                                width: parent.width
                                text: root.contentCache[entryRow.modelData.id] !== undefined
                                      ? root.contentCache[entryRow.modelData.id]
                                      : "Loading excerpt…"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                opacity: 0.9
                                wrapMode: Text.WordWrap
                                maximumLineCount: 9
                                elide: Text.ElideRight
                            }

                            StyledText {
                                visible: entryRow.modelData.originUrl !== ""
                                width: parent.width
                                text: "Origin: " + entryRow.modelData.originUrl
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            Flow {
                                width: parent.width
                                spacing: Theme.spacingXS
                                visible: entryRow.modelData.tags.length > 0

                                Repeater {
                                    model: entryRow.modelData.tags

                                    delegate: Rectangle {
                                        required property string modelData
                                        width: tagLabel.implicitWidth + Theme.spacingS * 2
                                        height: 20
                                        radius: 10
                                        color: Theme.withAlpha(Theme.primary, 0.15)

                                        StyledText {
                                            id: tagLabel
                                            anchors.centerIn: parent
                                            text: parent.modelData
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.primary
                                        }
                                    }
                                }
                            }

                            Row {
                                spacing: Theme.spacingXS

                                DankActionButton {
                                    iconName: "content_copy"
                                    buttonSize: 26
                                    iconColor: Theme.surfaceVariantText
                                    onClicked: root.copyUrl(entryRow.modelData)
                                }

                                DankActionButton {
                                    iconName: "sync"
                                    buttonSize: 26
                                    iconColor: Theme.surfaceVariantText
                                    onClicked: root.reloadEntry(entryRow.modelData)
                                }

                                DankActionButton {
                                    iconName: root.pendingDeleteId === entryRow.modelData.id
                                              ? "delete_forever" : "delete"
                                    buttonSize: 26
                                    iconColor: root.pendingDeleteId === entryRow.modelData.id
                                               ? Theme.error : Theme.surfaceVariantText
                                    onClicked: root.requestDelete(entryRow.modelData)
                                }

                                StyledText {
                                    visible: root.pendingDeleteId === entryRow.modelData.id
                                    text: "click again to delete"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.error
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }

                footer: Item {
                    width: entryList.width
                    height: root.page < root.pages ? 40 : 0
                    visible: root.page < root.pages

                    Rectangle {
                        anchors.centerIn: parent
                        width: moreLabel.implicitWidth + Theme.spacingL * 2
                        height: 28
                        radius: Theme.cornerRadius
                        color: moreArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                        StyledText {
                            id: moreLabel
                            anchors.centerIn: parent
                            text: root.isLoading ? "Loading…" : "Load more"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        MouseArea {
                            id: moreArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.loadMore()
                        }
                    }
                }

                }

                // Empty state (overlaid on the list)
                Column {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: root.entries.length === 0
                    width: parent.width - Theme.spacingXL * 2

                    WallabagIcon {
                        size: 48
                        full: true
                        iconColor: Theme.surfaceVariantText
                        iconOpacity: 0.5
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    StyledText {
                        width: parent.width
                        text: {
                            if (!root.configured)
                                return "Set the URL, client ID, username and secrets in Settings → Plugins → Wallabag"
                            if (root.isLoading)
                                return "Loading entries…"
                            if (root.errorMessage !== "")
                                return root.errorMessage
                            if (root.searchTerm !== "")
                                return "No results for \u201C" + root.searchTerm + "\u201D"
                            return "No entries in this view"
                        }
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }
}
