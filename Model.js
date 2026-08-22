.pragma library

// Pure, deliberately boring policy for Trace.  The helper is the trust
// boundary for credentials and HTTP; this file is the trust boundary for
// anything that reaches a QML Text item. control characters are removed here.
var MAX_TEXT = 240
var MAX_SHORT_TEXT = 96
var MAX_ARRAY = 120

function text(value, limit) {
  var valueText = String(value === undefined || value === null ? "" : value)
  valueText = valueText.replace(/[\u0000-\u001f\u007f-\u009f]/g, " ")
  valueText = valueText.replace(/\s+/g, " ").trim()
  var max = Math.max(4, Math.floor(Number(limit) || MAX_TEXT))
  return valueText.length > max ? valueText.substring(0, max - 1) + "…" : valueText
}

function sanitize(value) { return text(value, MAX_TEXT) }
function shortText(value) { return text(value, MAX_SHORT_TEXT) }

function safeUrl(value) {
  var result = text(value, 1000)
  return /^https?:\/\/[^\s]+$/i.test(result) ? result : ""
}

function number(value, fallback, minimum) {
  var n = Number(value)
  if (!isFinite(n)) n = Number(fallback) || 0
  if (minimum !== undefined && n < minimum) n = minimum
  return n
}

function bool(value) { return value === true || value === 1 || value === "true" }

function priority(value) {
  var raw = String(value === undefined || value === null ? "" : value).toLowerCase()
  if (raw === "3" || raw === "high" || raw === "urgent") return "high"
  if (raw === "2" || raw === "medium" || raw === "normal") return "medium"
  if (raw === "1" || raw === "low") return "low"
  return raw === "" ? "" : shortText(raw)
}

function copyObject(value) {
  var result = {}
  if (!value || typeof value !== "object" || Array.isArray(value)) return result
  for (var key in value) result[key] = value[key]
  return result
}

function stringArray(value, limit) {
  var source = Array.isArray(value) ? value : []
  var result = []
  var max = limit || MAX_ARRAY
  for (var i = 0; i < source.length && i < max; i++) {
    if (source[i] === null || source[i] === undefined) continue
    result.push(sanitize(source[i]))
  }
  return result
}

function assigned(value) {
  if (!value) return null
  if (typeof value === "string") return shortText(value)
  return shortText(value.name || value.username || value.email || value.id)
}

function normalizeIssue(raw) {
  var source = raw && typeof raw === "object" ? raw : {}
  var issue = {
    id: shortText(source.id),
    shortId: shortText(source.shortId || source.short_id),
    title: sanitize(source.title),
    culprit: sanitize(source.culprit),
    project: sanitize(source.project),
    environment: sanitize(source.environment),
    level: shortText(source.level || "error"),
    status: shortText(source.status || "unresolved"),
    substatus: shortText(source.substatus),
    priority: priority(source.priority),
    hasSeen: source.hasSeen === undefined ? true : bool(source.hasSeen),
    inInbox: source.inInbox === undefined ? false : bool(source.inInbox),
    isUnhandled: bool(source.isUnhandled),
    isRegression: bool(source.isRegression || source.regression),
    count: number(source.count, 0, 0),
    userCount: number(source.userCount || source.user_count, 0, 0),
    firstSeen: shortText(source.firstSeen || source.first_seen),
    lastSeen: shortText(source.lastSeen || source.last_seen),
    assignedTo: assigned(source.assignedTo || source.assigned_to),
    permalink: safeUrl(source.permalink || source.url),
    regressionId: shortText(source.regressionId || source.regression_id || source.fingerprint)
  }
  // Keep fixture/provider extensions useful without allowing arbitrary remote
  // objects into the UI model.
  if (source.metadata) issue.metadata = normalizeMetadata(source.metadata)
  return issue
}

function normalizeMetadata(value) {
  var source = value && typeof value === "object" ? value : {}
  var result = {}
  var keys = Object.keys(source)
  for (var i = 0; i < keys.length && i < 40; i++) {
    var key = shortText(keys[i])
    if (!key) continue
    result[key] = sanitize(source[key])
  }
  return result
}

function normalizeTags(value) {
  var source = Array.isArray(value) ? value : []
  var result = []
  for (var i = 0; i < source.length && i < MAX_ARRAY; i++) {
    if (source[i] && typeof source[i] === "object") {
      result.push({ key: shortText(source[i].key || source[i].name), value: sanitize(source[i].value) })
    } else result.push({ key: "", value: sanitize(source[i]) })
  }
  return result
}

function normalizeFrame(raw) {
  var source = raw && typeof raw === "object" ? raw : {}
  return {
    filename: sanitize(source.filename),
    function: sanitize(source.function || source.functionName),
    module: shortText(source.module),
    line: number(source.line, 0, 0),
    column: number(source.column, 0, 0),
    context: Array.isArray(source.context) ? stringArray(source.context, 30).join("\n") : sanitize(source.context),
    inApp: source.inApp === true,
    vars: normalizeMetadata(source.vars)
  }
}

function normalizeDetail(raw) {
  var source = raw && typeof raw === "object" ? raw : {}
  var issue = normalizeIssue(source.issue || source)
  var frames = Array.isArray(source.stacktrace) ? source.stacktrace
    : (source.stacktrace && Array.isArray(source.stacktrace.frames) ? source.stacktrace.frames : [])
  var breadcrumbs = Array.isArray(source.breadcrumbs) ? source.breadcrumbs : []
  var cleanBreadcrumbs = []
  for (var i = 0; i < breadcrumbs.length && i < MAX_ARRAY; i++) {
    var crumb = breadcrumbs[i] && typeof breadcrumbs[i] === "object" ? breadcrumbs[i] : {}
    cleanBreadcrumbs.push({
      timestamp: shortText(crumb.timestamp),
      category: shortText(crumb.category),
      level: shortText(crumb.level),
      message: sanitize(crumb.message || crumb.data)
    })
  }
  issue.metadata = normalizeMetadata(source.metadata || issue.metadata)
  issue.tags = normalizeTags(source.tags)
  issue.stacktrace = frames.slice(0, MAX_ARRAY).map(normalizeFrame)
  issue.breadcrumbs = cleanBreadcrumbs
  return issue
}

function emptyState(message) {
  return {
    schemaVersion: 1,
    state: "error",
    message: sanitize(message || "Trace returned no data."),
    configured: false,
    ready: false,
    demoMode: false,
    issues: [],
    fetchedAt: ""
  }
}

function parseState(raw) {
  var source = raw
  if (typeof raw === "string") {
    try { source = JSON.parse(raw) } catch (e) { return emptyState("Trace returned unreadable data.") }
  }
  if (!source || typeof source !== "object" || Array.isArray(source))
    return emptyState("Trace returned an invalid state document.")

  var result = emptyState("")
  var providedMessage = sanitize(source.message || (source.error && source.error.message))
  result.message = ""
  result.schemaVersion = Number(source.schemaVersion) === 1 ? 1 : 1
  var stateName = String(source.state || "")
  if (stateName === "unconfigured" || stateName === "needs-token" || stateName === "setup") stateName = "setup"
  if (stateName === "stale") {
    result.state = "error"
    result.message = providedMessage || "Showing cached issues — Sentry is unavailable."
  } else {
    result.state = ["loading", "ready", "error", "setup"].indexOf(stateName) >= 0 ? stateName : "error"
    result.message = providedMessage
  }
  result.configured = source.configured === true
  result.ready = source.ready === true || result.state === "ready"
  result.demoMode = source.demoMode === true || source.demo === true
  result.fetchedAt = shortText(source.fetchedAt || source.lastFetchedAt)
  result.configPath = shortText(source.configPath)
  var list = Array.isArray(source.issues) ? source.issues : []
  result.issues = list.slice(0, MAX_ARRAY).map(normalizeIssue)
  result.issueCount = number(source.issueCount, result.issues.length, 0)
  result.regressionCount = number(source.regressionCount,
    result.issues.filter(function (item) { return item.isRegression }).length, 0)
  return result
}

function matchesFilter(issue, filter) {
  var mode = String(filter || "unresolved").toLowerCase()
  if (mode === "all") return true
  if (mode === "regressions" || mode === "regression") return issue.isRegression
  if (mode === "unhandled") return issue.isUnhandled
  return String(issue.status).toLowerCase() === "unresolved" || issue.status === ""
}

function matchesSearch(issue, query) {
  var needle = String(query || "").toLowerCase().trim()
  if (!needle) return true
  var haystack = [issue.id, issue.shortId, issue.title, issue.culprit,
    issue.project, issue.environment, issue.level].join(" ").toLowerCase()
  return haystack.indexOf(needle) >= 0
}

function visibleIssues(issues, filter, search, projectFilter) {
  var source = Array.isArray(issues) ? issues : []
  return triageOrder(source.filter(function (issue) {
    var project = String(projectFilter || "all")
    return matchesFilter(issue, filter) && matchesSearch(issue, search)
      && (project === "all" || String(issue.project || "") === project)
  }))
}

function isAttention(issue) {
  if (!issue) return false
  return issue.isRegression || issue.hasSeen === false || issue.inInbox === true
    || String(issue.substatus || "").toLowerCase() === "new"
}

function priorityRank(value) {
  var name = priority(value)
  return name === "high" ? 3 : (name === "medium" ? 2 : (name === "low" ? 1 : 0))
}

function newestEpoch(value) {
  var parsed = Date.parse(String(value || ""))
  return isFinite(parsed) ? parsed : 0
}

function triageOrder(issues) {
  var source = Array.isArray(issues) ? issues : []
  return source.map(function (issue, index) { return { issue: issue, index: index } }).sort(function (a, b) {
    var ar = a.issue && a.issue.isRegression ? 1 : 0
    var br = b.issue && b.issue.isRegression ? 1 : 0
    if (ar !== br) return br - ar
    var aa = isAttention(a.issue) ? 1 : 0
    var ba = isAttention(b.issue) ? 1 : 0
    if (aa !== ba) return ba - aa
    var ap = priorityRank(a.issue && a.issue.priority)
    var bp = priorityRank(b.issue && b.issue.priority)
    if (ap !== bp) return bp - ap
    var at = newestEpoch(a.issue && a.issue.lastSeen)
    var bt = newestEpoch(b.issue && b.issue.lastSeen)
    if (at !== bt) return bt - at
    return a.index - b.index
  }).map(function (entry) { return entry.issue })
}

function projectOptions(issues) {
  var names = {}
  ;(Array.isArray(issues) ? issues : []).forEach(function (issue) {
    var project = shortText(issue && issue.project)
    if (project) names[project] = true
  })
  return Object.keys(names).sort(function (a, b) { return a.localeCompare(b) })
}

function applyDemoAction(issues, action, id) {
  var source = Array.isArray(issues) ? issues : []
  var verb = String(action || "")
  var target = String(id || "")
  var result = []
  for (var i = 0; i < source.length; i++) {
    var issue = source[i]
    if (!issue || String(issue.id) !== target) { result.push(issue); continue }
    if (verb === "resolve" || verb === "ignore") continue
    var next = {}
    for (var key in issue) next[key] = issue[key]
    if (verb === "assign") next.assignedTo = "You"
    if (verb === "review") {
      next.hasSeen = true
      next.inInbox = false
      if (String(next.substatus || "").toLowerCase() === "new") next.substatus = "ongoing"
    }
    result.push(next)
  }
  return result
}

function regressionCount(issues) {
  return (Array.isArray(issues) ? issues : []).filter(function (item) { return item && item.isRegression }).length
}

function unreadCount(issues) {
  return (Array.isArray(issues) ? issues : []).filter(function (item) {
    return isAttention(item)
  }).length
}

function issueIndex(issues, id) {
  var value = String(id || "")
  var source = Array.isArray(issues) ? issues : []
  for (var i = 0; i < source.length; i++) if (String(source[i].id) === value) return i
  return -1
}

function clampIndex(index, count) {
  var n = Math.floor(Number(index) || 0)
  var max = Math.max(0, Math.floor(Number(count) || 0) - 1)
  return Math.max(0, Math.min(max, n))
}

function relativeTime(value, now) {
  var then = Date.parse(String(value || ""))
  if (!isFinite(then)) return ""
  var current = now === undefined ? Date.now() : Number(now)
  var seconds = Math.max(0, Math.floor((current - then) / 1000))
  if (seconds < 60) return "just now"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 30) return days + "d ago"
  var months = Math.floor(days / 30)
  if (months < 12) return months + "mo ago"
  return Math.floor(months / 12) + "y ago"
}

function timeLabel(value, now) { return relativeTime(value, now) }

function regressionIdentity(issue) {
  if (!issue) return ""
  var id = String(issue.id || "")
  if (!id || !issue.isRegression) return ""
  return safeIssueId(id) ? id : ""
}

function newRegressions(issues, seen) {
  var source = Array.isArray(issues) ? issues : []
  var known = seen || {}
  return source.filter(function (issue) {
    var identity = regressionIdentity(issue)
    return identity !== "" && !known[identity]
  })
}

function badgeText(count) {
  var n = Math.max(0, Math.floor(Number(count) || 0))
  return n === 0 ? "" : (n > 99 ? "99+" : String(n))
}

function barTooltip(state, count, configured, demo) {
  if (demo) return "Trace · Demo data"
  if (!configured || state === "setup") return "Trace · Set up Sentry"
  if (state === "error") return "Trace · " + (count > 0 ? "Sentry unavailable" : "Disconnected")
  return count > 0 ? "Trace · " + count + " issue" + (count === 1 ? "" : "s") + " needs attention" : "Trace · Nothing needs attention"
}

function safeIssueId(value) { return /^[A-Za-z0-9_.:-]{1,160}$/.test(String(value || "")) }

function ignoreDuration(value) {
  var n = Number(value)
  return [30, 60, 240, 1440, 10080].indexOf(n) >= 0 ? n : 60
}
