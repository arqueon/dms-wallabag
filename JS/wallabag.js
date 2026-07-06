// wallabag.js — pure stateless helpers for the DMS Wallabag plugin

function parseCurl(stdout, exitCode) {
    // curl runs with -w "\n%{http_code}": the last line is the HTTP status
    var raw = String(stdout || "")
    if (exitCode !== 0 && raw.trim() === "")
        return { status: 0, json: null, error: "curl exited with code " + exitCode }
    var cut = raw.lastIndexOf("\n")
    var statusStr = cut >= 0 ? raw.slice(cut + 1).trim() : raw.trim()
    var body = cut >= 0 ? raw.slice(0, cut) : ""
    var status = parseInt(statusStr)
    if (isNaN(status))
        return { status: 0, json: null, error: "unreadable curl response" }
    var json = null
    if (body.trim() !== "") {
        try { json = JSON.parse(body) } catch (e) { json = null }
    }
    return { status: status, json: json, error: null }
}

function errorText(res) {
    if (!res) return "no response"
    if (res.error) return res.error
    if (res.json && res.json.error_description) return res.json.error_description
    if (res.json && res.json.error) {
        var msg = res.json.error
        if (typeof msg === "object" && msg.message) return msg.message
        return String(msg)
    }
    if (res.status === 0) return "no connection to the server"
    if (res.status === 401) return "credentials rejected (401)"
    if (res.status === 403) return "access denied (403)"
    if (res.status === 404) return "not found (404)"
    return "HTTP error " + res.status
}

function buildQuery(params) {
    var parts = []
    for (var key in params) {
        if (params[key] === undefined || params[key] === null)
            continue
        parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(params[key])))
    }
    return parts.join("&")
}

function domainOf(url) {
    var m = String(url || "").match(/^[a-z]+:\/\/([^\/:?#]+)/i)
    return m ? m[1].replace(/^www\./, "") : ""
}

function mapEntry(json) {
    if (!json) return null
    return {
        id: json.id,
        title: (json.title || "").trim() || json.url || "(untitled)",
        url: json.url || json.given_url || "",
        givenUrl: json.given_url || "",
        originUrl: json.origin_url || "",
        domain: json.domain_name || domainOf(json.url),
        previewPicture: json.preview_picture || "",
        readingTime: json.reading_time || 0,
        createdAt: json.created_at || "",
        isArchived: !!parseInt(json.is_archived || 0),
        isStarred: !!parseInt(json.is_starred || 0),
        language: json.language || "",
        publishedBy: (json.published_by || []).filter(function(a) { return !!a }),
        annotationCount: (json.annotations || []).length,
        tags: (json.tags || []).map(function(t) { return t.label })
    }
}

function mapEntries(items) {
    var out = []
    for (var i = 0; i < (items || []).length; i++) {
        var e = mapEntry(items[i])
        if (e) out.push(e)
    }
    return out
}

function excerpt(html, maxChars) {
    var text = String(html || "")
        .replace(/<style[\s\S]*?<\/style>/gi, " ")
        .replace(/<script[\s\S]*?<\/script>/gi, " ")
        .replace(/<\/(p|div|h[1-6]|li|br)>/gi, " ")
        .replace(/<[^>]+>/g, "")
        .replace(/&nbsp;/gi, " ")
        .replace(/&amp;/gi, "&")
        .replace(/&lt;/gi, "<")
        .replace(/&gt;/gi, ">")
        .replace(/&quot;/gi, "\"")
        .replace(/&#0?39;|&apos;/gi, "'")
        .replace(/\s+/g, " ")
        .trim()
    if (text.length > maxChars)
        return text.slice(0, maxChars).replace(/\s+\S*$/, "") + "…"
    return text
}

function relativeTime(isoDate) {
    if (!isoDate) return ""
    var then = Date.parse(isoDate)
    if (isNaN(then)) return ""
    var mins = Math.floor((Date.now() - then) / 60000)
    if (mins < 1) return "now"
    if (mins < 60) return mins + " min ago"
    var hours = Math.floor(mins / 60)
    if (hours < 24) return hours + " h ago"
    var days = Math.floor(hours / 24)
    if (days === 1) return "yesterday"
    if (days < 30) return days + " days ago"
    var d = new Date(then)
    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    var label = d.getDate() + " " + months[d.getMonth()]
    if (d.getFullYear() !== new Date().getFullYear())
        label += " " + d.getFullYear()
    return label
}

function formatCount(n) {
    return n > 99 ? "99+" : String(n)
}
