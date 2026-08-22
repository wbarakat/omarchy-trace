import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The singleton is intentionally headless.  It stays alive with the shell,
// which means the bar remains useful while the tiled window is closed.
Item {
  id: root

  visible: false
  width: 0
  height: 0

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null

  readonly property string pluginDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) : String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string helperPath: pluginDir + "/scripts/trace-api.sh"

  property var settings: defaultSettingValues
  readonly property var defaultSettingValues: ({
    baseUrl: "https://sentry.io",
    organization: "",
    projects: "",
    refreshIntervalSec: 120,
    maxIssues: 50,
    notifyRegressions: true
  })

  property string state: "loading"
  property string message: "Loading Trace…"
  property bool ready: false
  property bool configured: false
  property bool demoMode: false
  property var issues: []
  property var selectedDetail: null
  property int selectedIndex: 0
  property bool loading: false
  property bool detailLoading: false
  property string lastFetchedAt: ""
  property string filter: "unresolved"
  property string search: ""
  property string projectFilter: "all"
  property bool windowOpen: false

  readonly property var visibleIssues: Model.visibleIssues(issues, filter, search, projectFilter)
  readonly property var projectOptions: Model.projectOptions(issues)
  readonly property int unreadCount: Model.unreadCount(issues)
  readonly property int regressionCount: Model.regressionCount(issues)
  readonly property var selectedIssue: visibleIssues.length > 0
    ? visibleIssues[Model.clampIndex(selectedIndex, visibleIssues.length)] : null
  readonly property string barTooltip: Model.barTooltip(state, unreadCount, configured, demoMode)

  property string _stdout: ""
  property string _stderr: ""
  property string _inputPayload: ""
  property var _queue: []
  property string _currentOperation: ""
  property string _currentIssueId: ""
  property bool _currentDemo: false
  property bool _notificationsPrimed: false
  // Regression membership is compared between live polls. When an issue
  // leaves the regressed set it is forgotten, so a later genuine regression
  // can alert again without lastSeen timestamp churn creating duplicates.
  property var _activeRegressions: ({})
  property string _selectedId: ""
  property string _agentPrompt: ""
  property string _agentStdout: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function applySettings(values) {
    var next = {}
    for (var key in defaultSettingValues) next[key] = defaultSettingValues[key]
    var source = values || {}
    for (var name in source) {
      if (source[name] !== undefined && source[name] !== null) next[name] = source[name]
    }
    settings = next
    if (configured && !demoMode) refresh()
  }

  function applyState(raw) {
    var parsed = Model.parseState(raw)
    var previousId = _selectedId || (selectedIssue ? selectedIssue.id : "")
    state = parsed.state
    message = parsed.message || (parsed.state === "ready" ? ""
      : (parsed.state === "setup" ? "Connect Trace to Sentry." : "Trace is unavailable."))
    ready = parsed.ready
    configured = _currentDemo ? true : parsed.configured
    demoMode = _currentDemo ? true : parsed.demoMode
    if (_currentDemo) ready = true
    issues = parsed.issues
    lastFetchedAt = parsed.fetchedAt || new Date().toISOString()
    if (previousId) {
      var nextIndex = Model.issueIndex(visibleIssues, previousId)
      selectedIndex = nextIndex >= 0 ? nextIndex : Model.clampIndex(selectedIndex, visibleIssues.length)
    } else selectedIndex = Model.clampIndex(selectedIndex, visibleIssues.length)
    if (windowOpen && selectedIssue
        && (!selectedDetail || String(selectedDetail.id || "") !== String(selectedIssue.id || "")))
      loadDetail(selectedIssue)
    if (demoMode) {
      _notificationsPrimed = false
      _activeRegressions = ({})
    } else {
      var previousRegressions = _activeRegressions
      var currentRegressions = ({})
      for (var i = 0; i < issues.length; i++) {
        var currentId = Model.regressionIdentity(issues[i])
        if (currentId) currentRegressions[currentId] = true
      }
      if (_notificationsPrimed && setting("notifyRegressions", true) === true)
        notifyNewRegressions(issues, previousRegressions)
      _activeRegressions = currentRegressions
      _notificationsPrimed = true
    }
  }

  function notifyNewRegressions(list, previous) {
    var arrivals = Model.newRegressions(list, previous)
    for (var i = 0; i < arrivals.length; i++) {
      var identity = Model.regressionIdentity(arrivals[i])
      if (!identity) continue
      enqueue("notify", [], JSON.stringify({
        identity: identity,
        title: arrivals[i].shortId + " · " + arrivals[i].title,
        permalink: arrivals[i].permalink
      }))
    }
  }

  function refresh() {
    enqueue("list", [String(intSetting("maxIssues", 50, 10, 100))], "", demoMode)
  }

  function selectIndex(index) {
    if (visibleIssues.length === 0) { selectedIndex = 0; return }
    selectedIndex = Model.clampIndex(index, visibleIssues.length)
    _selectedId = selectedIssue ? selectedIssue.id : ""
  }

  function moveSelection(delta) { selectIndex(selectedIndex + (Number(delta) < 0 ? -1 : 1)) }

  function openSelected() {
    if (!selectedIssue) return
    _selectedId = selectedIssue.id
    loadDetail(selectedIssue.id)
  }

  function openWindow() { windowOpen = true }
  function closeWindow() { windowOpen = false; detailLoading = false }

  function back() { selectedDetail = null; detailLoading = false }

  function setFilter(value) {
    filter = ["unresolved", "regressions", "all", "unhandled"].indexOf(String(value)) >= 0
      ? String(value) : "unresolved"
    selectIndex(0)
    selectedDetail = null
    if (windowOpen && selectedIssue) loadDetail(selectedIssue)
  }

  function setSearch(value) {
    search = Model.sanitize(value)
    selectIndex(0)
    // Search changes on every keystroke. Clear a stale detail immediately,
    // then let explicit selection/navigation fetch the full replacement.
    selectedDetail = null
  }

  function setProjectFilter(value) {
    var requested = String(value || "all")
    projectFilter = requested === "all" || projectOptions.indexOf(requested) >= 0 ? requested : "all"
    selectIndex(0)
    selectedDetail = null
    if (windowOpen && selectedIssue) loadDetail(selectedIssue)
  }

  function loadDetail(issueId) {
    var id = issueId && typeof issueId === "object" ? issueId.id : issueId
    id = String(id || (selectedIssue ? selectedIssue.id : ""))
    if (!Model.safeIssueId(id)) return
    detailLoading = true
    enqueue("detail", [id], "", demoMode)
  }

  function action(kind, issueId, extra) {
    var id = issueId && typeof issueId === "object" ? issueId.id : issueId
    id = String(id || (selectedIssue ? selectedIssue.id : ""))
    if (!Model.safeIssueId(id)) return
    enqueue(kind, [id].concat(extra || []), "", demoMode)
  }

  function resolveIssue(issueId) { action("resolve", issueId) }
  function assignIssue(issueId) { action("assign", issueId) }
  function ignoreIssue(issueId, durationMinutes) { action("ignore", issueId, [String(Model.ignoreDuration(durationMinutes))]) }
  function reviewIssue(issueId) { action("review", issueId) }

  function openIssue(issue) {
    var item = issue || selectedIssue
    var url = Model.safeUrl(item && item.permalink)
    if (url) Quickshell.execDetached(["omarchy-launch-browser", url])
  }

  function copyIssue(issue) {
    var item = issue || selectedIssue
    var url = Model.safeUrl(item && item.permalink)
    if (url) Quickshell.execDetached(["wl-copy", "--", url])
  }

  function explainIssue(issue, detail) {
    if (agentProbe.running) {
      message = "Agent handoff is already starting."
      return
    }
    var prompt = Model.agentPrompt(issue || selectedIssue, detail || selectedDetail)
    if (!prompt) {
      message = "Select an issue before handing it off."
      return
    }
    _agentPrompt = prompt
    _agentStdout = ""
    agentProbe.running = true
  }

  // The token is deliberately absent from command.  Process.write is used
  // after start and the helper reads one JSON line, then continues without
  // waiting for EOF (Quickshell keeps stdin open).
  function saveSetup(values, organization, projects, environments, token) {
    var source
    if (typeof values === "object") source = values || {}
    else if (arguments.length >= 5) source = {
      baseUrl: values, organization: organization, projects: projects,
      environments: environments, token: token
    }
    else source = { baseUrl: values, organization: organization, projects: projects, token: environments }
    var payload = {
      baseUrl: Model.safeUrl(source.baseUrl || setting("baseUrl", "https://sentry.io")) || "https://sentry.io",
      organization: Model.shortText(source.organization || ""),
      projects: Model.shortText(source.projects || ""),
      environments: Model.shortText(source.environments || source.environment || ""),
      token: String(source.token || "")
    }
    enqueue("configure", ["--token-stdin"], JSON.stringify(payload))
  }

  function enableDemo() { demoMode = true; configured = true; refresh() }
  function disableDemo() {
    demoMode = false
    configured = false
    issues = []
    selectedDetail = null
    enqueue("status", [])
  }
  function clearCredentials() { enqueue("clear-token", []) }

  Component.onCompleted: enqueue("status", [])

  function enqueue(operation, args, payload, demo) {
    var entry = { operation: String(operation), args: args || [], payload: payload || "", demo: demo === true }
    _queue = _queue.concat([entry])
    pump()
  }

  function pump() {
    if (apiProcess.running || _queue.length === 0) return
    var entry = _queue[0]
    _queue = _queue.slice(1)
    _inputPayload = entry.payload || ""
    _stdout = ""
    _stderr = ""
    var command = [helperPath]
    if (entry.demo) command.push("--demo")
    command.push(entry.operation)
    for (var i = 0; i < entry.args.length; i++) command.push(String(entry.args[i]))
    _currentOperation = entry.operation
    _currentIssueId = entry.args.length > 0 ? String(entry.args[0]) : ""
    _currentDemo = entry.demo === true
    apiProcess.command = command
    if (entry.operation === "list") loading = true
    if (entry.operation === "detail") detailLoading = true
    apiProcess.running = true
  }

  Timer {
    interval: root.intSetting("refreshIntervalSec", 120, 30, 3600) * 1000
    repeat: true
    running: root.configured || root.demoMode
    onTriggered: root.refresh()
  }

  Process {
    id: agentProbe
    command: ["omarchy", "default", "agent"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._agentStdout = text
    }
    onExited: function(exitCode) {
      var prompt = root._agentPrompt
      root._agentPrompt = ""
      if (exitCode !== 0) {
        root.message = "Could not determine the default Omarchy agent."
        return
      }
      var agent = Model.shortText(root._agentStdout)
      if (!agent) {
        root.message = "Choose a default agent, then press [i] again."
        Quickshell.execDetached(["omarchy", "menu", "summon", "setup.default.agent"])
        return
      }
      Quickshell.execDetached(["omarchy", "agent", "prompt", prompt])
      root.message = "Handed off to " + agent + "."
    }
  }

  Process {
    id: apiProcess
    command: []
    stdinEnabled: true

    onStarted: {
      if (root._inputPayload !== "") {
        write(root._inputPayload + "\n")
        root._inputPayload = ""
      }
    }
    stdout: StdioCollector { id: apiOutput; waitForEnd: true; onStreamFinished: root._stdout = text }
    stderr: StdioCollector { id: apiErrors; waitForEnd: true; onStreamFinished: root._stderr = text }
    onExited: function(exitCode) {
      var operation = ""
      // The command remains available until the next pump, so operation is
      // read from argv rather than stored in a second mutable state object.
      operation = root._currentOperation
      root.loading = operation === "list" ? false : root.loading
      root.detailLoading = operation === "detail" ? false : root.detailLoading
      var output = String(apiOutput.text || root._stdout || "").trim()
      var isAction = ["resolve", "assign", "ignore", "review", "configure", "clear-token"].indexOf(operation) >= 0
      if (output !== "") {
        if (operation === "status") {
          root.applyState(output)
          if (root.configured && !root.demoMode) root.refresh()
        } else if (operation === "detail") {
          try {
            var detailData = JSON.parse(output)
            if (exitCode === 0 && detailData && detailData.state !== "error") root.selectedDetail = Model.normalizeDetail(detailData)
            else if (detailData.message || (detailData.error && detailData.error.message))
              root.message = Model.sanitize(detailData.message || detailData.error.message)
          } catch (e) { root.message = "Trace returned an unreadable issue detail." }
        } else if (operation !== "notify") {
          var actionResponse = null
          try { actionResponse = JSON.parse(output) } catch (ignore) {}
          if (isAction && actionResponse && (actionResponse.ok === false || actionResponse.state === "error")) {
            root.message = Model.sanitize(actionResponse.message
              || (actionResponse.error && actionResponse.error.message) || "Trace action failed.")
          } else if (isAction && actionResponse && actionResponse.issues) {
            root.applyState(output)
          } else if (isAction) {
            // A successful mutation may return only an acknowledgement. The
            // next fetch is authoritative, so do not optimistically invent a
            // changed issue row.
            if (operation === "clear-token") {
              root.configured = false
              root.ready = false
              root.state = "setup"
              root.message = "Trace disconnected."
              root.issues = []
              root.selectedDetail = null
            } else if (root._currentDemo && operation !== "configure") {
              root.issues = Model.applyDemoAction(root.issues, operation, root._currentIssueId)
              root.selectedDetail = null
              root.message = operation === "review" ? "Issue marked reviewed." : "Demo action applied."
            } else {
              if (operation === "configure") root.configured = true
              root.refresh()
            }
          } else {
            root.applyState(output)
          }
        }
      } else if (exitCode === 0 && isAction) {
        if (operation === "clear-token") {
          root.configured = false
          root.ready = false
          root.state = "setup"
          root.message = "Trace disconnected."
          root.issues = []
          root.selectedDetail = null
        } else if (root._currentDemo && operation !== "configure") {
          root.issues = Model.applyDemoAction(root.issues, operation, root._currentIssueId)
          root.selectedDetail = null
          root.message = operation === "review" ? "Issue marked reviewed." : "Demo action applied."
        } else {
          if (operation === "configure") root.configured = true
          root.refresh()
        }
      } else if (exitCode !== 0 && operation !== "notify") {
        root.state = "error"
        root.ready = false
        root.message = Model.sanitize(apiErrors.text || root._stderr || "Trace helper failed.")
      }
      root._inputPayload = ""
      Qt.callLater(root.pump)
    }
  }
}
