import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "components"

Item {
  id: root
  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false
  property bool closingFromHost: false
  property string page: "inbox" // inbox, settings
  property string narrowView: "list" // list, detail
  property string query: ""
  property string filter: "unresolved"
  property bool helpVisible: false
  property string pendingAction: ""
  property string pendingG: ""

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "wbarakat.trace"
  readonly property bool compact: window.width < Style.space(760)
  readonly property bool configured: !!service && (service.configured || service.demoMode)
  readonly property var issues: service && service.visibleIssues ? service.visibleIssues : []
  readonly property var selectedIssue: service ? service.selectedIssue : null
  readonly property var projectOptions: service && service.projectOptions ? service.projectOptions : []
  readonly property string projectFilter: service && service.projectFilter ? String(service.projectFilter) : "all"
  readonly property string statusText: service ? clean(service.message, 280) : "Starting Trace…"
  readonly property bool commandShortcutsEnabled: opened && configured && page === "inbox" && pendingAction === "" && !helpVisible && !search.activeFocus && !ignoreMenu.visible && !projectMenu.visible

  function clean(value, limit) {
    var text = String(value === undefined || value === null ? "" : value).replace(/[\u0000-\u001f\u007f]/g, " ")
    return text.length > limit ? text.slice(0, limit - 1) + "…" : text
  }
  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }
  function restoreKeyboardFocus() { focusRestore.restart() }
  function open(payloadJson) {
    opened = true; closingFromHost = false
    var payload = ({})
    try { payload = JSON.parse(String(payloadJson || "{}")) || ({}) } catch (e) {}
    if (service && typeof service.openWindow === "function") service.openWindow()
    if (payload.filter) setFilter(String(payload.filter))
    if (service && typeof service.refresh === "function" && (service.configured || service.demoMode)) service.refresh()
    restoreKeyboardFocus()
  }
  function close() {
    closingFromHost = true
    opened = false
    if (service && typeof service.closeWindow === "function") service.closeWindow()
    closingFromHost = false
  }
  function setFilter(name) { filter = name; if (service) service.setFilter(name) }
  function setProjectFilter(value) {
    if (service && typeof service.setProjectFilter === "function") service.setProjectFilter(String(value || "all"))
  }
  function projectLabel(value) { return value === "all" ? "all projects" : clean(value, 14) }
  function openProjectMenu() {
    var current = projectFilter === "all" ? 0 : projectOptions.indexOf(projectFilter) + 1
    projectMenu.selectedIndex = Math.max(0, current)
    projectMenu.open()
  }
  function moveProjectMenu(delta) { if (projectMenu.visible) projectMenu.moveChoice(Number(delta)) }
  function chooseProjectMenu() { if (projectMenu.visible) projectMenu.choose() }
  function openIgnoreMenu() {
    ignoreMenu.selectedIndex = 0
    ignoreMenu.open()
  }
  function moveIgnoreMenu(delta) { if (ignoreMenu.visible) ignoreMenu.moveChoice(Number(delta)) }
  function chooseIgnoreMenu() { if (ignoreMenu.visible) ignoreMenu.choose() }
  function select(index, showDetail) {
    if (!service || index < 0) return
    service.selectIndex(index)
    var issue = issues[index]
    if (issue && typeof service.loadDetail === "function") service.loadDetail(issue)
    if (showDetail || compact) narrowView = "detail"
  }
  function move(delta) {
    if (!service) return
    service.moveSelection(delta)
    if (service.selectedIssue && typeof service.loadDetail === "function") service.loadDetail(service.selectedIssue)
  }
  function openSelected() {
    if (!service) return
    if (typeof service.openSelected === "function") service.openSelected()
    if (service.selectedIssue && typeof service.loadDetail === "function") service.loadDetail(service.selectedIssue)
    narrowView = "detail"
  }
  function back() {
    if (pendingAction !== "") { pendingAction = ""; return }
    if (helpVisible) { helpVisible = false; return }
    if (page === "settings") { page = "inbox"; return }
    if (compact && narrowView === "detail") { narrowView = "list"; return }
    requestClose()
  }
  function actionLabel(action) {
    if (action === "resolve") return "Resolve this issue?"
    if (action === "assign") return "Assign this issue to you?"
    if (action === "review") return "Mark this issue reviewed?"
    if (action === "ignore60") return "Ignore this issue for one hour?"
    if (action === "ignore1440") return "Ignore this issue for one day?"
    if (action === "ignore10080") return "Ignore this issue for one week?"
    if (action === "disconnect") return "Remove the Trace connection?"
    return "Confirm action?"
  }
  function actionDescription(action) {
    if (action === "resolve") return "Moves it out of Trace’s unresolved inbox. It remains in Sentry as resolved."
    if (action === "assign") return "Keeps it in the inbox and assigns it to your Sentry account."
    if (action === "review") return "Keeps it unresolved, but removes its unreviewed attention state for you."
    if (action === "ignore60") return "Moves it out of the inbox for one hour, then Sentry can reactivate it."
    if (action === "ignore1440") return "Moves it out of the inbox for one day, then Sentry can reactivate it."
    if (action === "ignore10080") return "Moves it out of the inbox for one week, then Sentry can reactivate it."
    if (action === "disconnect") return "Removes this token, connection settings, and the cached issue list from this machine."
    return "This updates the issue in Sentry."
  }
  function perform(action) {
    if (!service) return
    var issue = service.selectedIssue
    if (action === "resolve" && issue) service.resolveIssue(issue)
    else if (action === "assign" && issue) service.assignIssue(issue)
    else if (action === "review" && issue && typeof service.reviewIssue === "function") service.reviewIssue(issue)
    else if (action.indexOf("ignore") === 0 && issue) service.ignoreIssue(issue, Number(action.slice(6)))
    else if (action === "disconnect") service.clearCredentials()
  }
  function confirm(action) { pendingAction = action }
  function runPending() { var action = pendingAction; pendingAction = ""; perform(action) }
  function demo() {
    if (!service) return
    if (service.demoMode) service.disableDemo()
    else service.enableDemo()
    page = "inbox"; narrowView = "list"
  }

  FloatingWindow {
    id: window
    visible: root.opened
    title: "Trace"
    color: Color.background
    implicitWidth: Style.space(1080)
    implicitHeight: Style.space(720)
    minimumSize: Qt.size(Style.space(510), Style.space(430))
    onVisibleChanged: if (!visible && root.opened && !root.closingFromHost) root.requestClose()

    FocusScope {
      id: keyboard
      anchors.fill: parent
      focus: true
      property bool typing: search.activeFocus
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (root.pendingAction !== "") {
          if (event.key === Qt.Key_Escape) root.pendingAction = ""
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.runPending()
          event.accepted = true
          return
        }
        if (root.helpVisible) { if (event.key === Qt.Key_Escape || event.text === "?" || event.key === Qt.Key_Return) root.helpVisible = false; event.accepted = true; return }
        if (event.key === Qt.Key_Escape) { root.back(); event.accepted = true; return }
        if (event.key === Qt.Key_F5) { if (root.service) root.service.refresh(); event.accepted = true; return }
        if (typing) { if (event.key === Qt.Key_Return) root.restoreKeyboardFocus(); return }
        if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_K) { search.forceActiveFocus(); event.accepted = true; return }
        if (event.text === "/") { search.forceActiveFocus(); event.accepted = true; return }
        if (event.text === "?") { root.helpVisible = true; event.accepted = true; return }
        if (event.text === "j" || event.key === Qt.Key_J || event.key === Qt.Key_Down) { root.move(1); event.accepted = true; return }
        if (event.text === "k" || event.key === Qt.Key_K || event.key === Qt.Key_Up) { root.move(-1); event.accepted = true; return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.openSelected(); event.accepted = true; return }
        if (event.text === "g" || event.key === Qt.Key_G) { root.pendingG = "g"; event.accepted = true; gTimer.restart(); return }
        if (root.pendingG === "g" && (event.text === "r" || event.key === Qt.Key_R)) { root.setFilter("regressions"); root.pendingG = ""; event.accepted = true; return }
        if (root.pendingG === "g" && (event.text === "u" || event.key === Qt.Key_U)) { root.setFilter("unresolved"); root.pendingG = ""; event.accepted = true; return }
      }
      Timer { id: gTimer; interval: 700; onTriggered: root.pendingG = "" }
      Timer { id: focusRestore; interval: 1; onTriggered: keyboard.forceActiveFocus() }

      // Letter commands are window shortcuts so a clicked control cannot strand
      // the keyboard workflow. Search and modal menus temporarily suspend them.
      Shortcut { sequence: "E"; enabled: root.commandShortcutsEnabled; onActivated: root.confirm("resolve") }
      Shortcut { sequence: "A"; enabled: root.commandShortcutsEnabled; onActivated: root.confirm("assign") }
      Shortcut { sequence: "X"; enabled: root.commandShortcutsEnabled; onActivated: root.confirm("review") }
      Shortcut { sequence: "Z"; enabled: root.commandShortcutsEnabled; onActivated: root.openIgnoreMenu() }
      Shortcut { sequence: "P"; enabled: root.commandShortcutsEnabled; onActivated: root.openProjectMenu() }
      Shortcut { sequence: "O"; enabled: root.commandShortcutsEnabled && !!root.selectedIssue; onActivated: root.service.openIssue(root.selectedIssue) }
      Shortcut { sequence: "Y"; enabled: root.commandShortcutsEnabled && !!root.selectedIssue; onActivated: root.service.copyIssue(root.selectedIssue) }
      Shortcut { sequence: "Return"; enabled: root.pendingAction !== "" && !ignoreMenu.visible && !projectMenu.visible; onActivated: root.runPending() }
      Shortcut { sequence: "Escape"; enabled: root.pendingAction !== "" && !ignoreMenu.visible && !projectMenu.visible; onActivated: root.pendingAction = "" }

      Rectangle { anchors.fill: parent; color: Color.background }
      Item {
        id: header
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        height: Style.space(50)
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: Style.space(1); color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, .2) }
        Row { anchors.left: parent.left; anchors.leftMargin: Style.space(14); anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(9)
          Text { text: "TRACE"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true }
          Text { text: root.service && root.service.demoMode ? "DEMO" : "SENTRY"; color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
          Text { visible: root.service && root.service.regressionCount > 0; text: root.service.regressionCount + " REGRESSED"; color: Color.urgent; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        }
        Row { anchors.right: parent.right; anchors.rightMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(5)
          TraceButton { text: "↻"; compact: true; tooltipText: "Refresh [F5]"; onClicked: if (root.service) root.service.refresh() }
          TraceButton { text: "?"; compact: true; tooltipText: "Keyboard shortcuts"; onClicked: root.helpVisible = true }
          TraceButton { text: "settings"; compact: true; onClicked: root.page = "settings" }
        }
      }
      SetupPage { anchors.top: header.bottom; anchors.bottom: footer.top; anchors.left: parent.left; anchors.right: parent.right; visible: !root.configured && root.page === "inbox"; service: root.service; onSaved: root.page = "inbox"; onDemoRequested: root.demo() }
      SettingsPage { anchors.top: header.bottom; anchors.bottom: footer.top; anchors.left: parent.left; anchors.right: parent.right; visible: root.page === "settings"; service: root.service; onBackRequested: root.page = "inbox"; onDemoRequested: root.demo(); onDisconnectRequested: root.confirm("disconnect") }
      Item {
        id: inbox
        anchors.top: header.bottom; anchors.bottom: footer.top; anchors.left: parent.left; anchors.right: parent.right
        visible: root.configured && root.page === "inbox"
        Item { id: controls; anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: Style.space(46)
          Row { anchors.left: parent.left; anchors.leftMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(5)
            TraceButton { text: "unresolved"; compact: true; active: root.filter === "unresolved"; onClicked: root.setFilter("unresolved") }
            TraceButton { text: "regressions"; compact: true; active: root.filter === "regressions"; onClicked: root.setFilter("regressions") }
            TraceButton { text: root.projectLabel(root.projectFilter) + " [p]"; compact: true; onClicked: root.openProjectMenu() }
          }
          TextField {
            id: search; anchors.right: parent.right; anchors.rightMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter
            width: Math.min(Style.space(270), parent.width - Style.space(325)); placeholderText: "search  /"; text: root.query
            onTextChanged: { root.query = text; if (root.service) root.service.setSearch(text) }
            Keys.onEscapePressed: root.restoreKeyboardFocus()
          }
        }
        IssueList { id: list; anchors.top: controls.bottom; anchors.bottom: parent.bottom; anchors.left: parent.left; width: root.compact ? parent.width : Math.round(parent.width * .43); visible: !root.compact || root.narrowView === "list"; issues: root.issues; selectedIssue: root.selectedIssue; loading: root.service && root.service.loading; query: root.query; onSelected: function(index) { root.select(index, false) }; onActivated: function(issue) { root.openSelected() } }
        IssueDetail { id: detail; anchors.top: controls.bottom; anchors.bottom: parent.bottom; anchors.left: root.compact ? parent.left : list.right; anchors.leftMargin: root.compact ? 0 : Style.space(5); anchors.right: parent.right; visible: !root.compact || root.narrowView === "detail"; issue: root.selectedIssue; detail: root.service ? root.service.selectedDetail : null; loading: root.service && root.service.detailLoading; onResolveRequested: root.confirm("resolve"); onAssignRequested: root.confirm("assign"); onReviewRequested: root.confirm("review"); onIgnoreRequested: root.openIgnoreMenu(); onOpenRequested: if (root.service && root.service.selectedIssue) root.service.openIssue(root.service.selectedIssue); onCopyRequested: if (root.service && root.service.selectedIssue) root.service.copyIssue(root.service.selectedIssue) }
      }
      Item {
        id: footer; anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; height: Style.space(29)
        Rectangle { anchors.top: parent.top; width: parent.width; height: Style.space(1); color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, .2) }
        Text { anchors.left: parent.left; anchors.leftMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter; width: parent.width - Style.space(160); text: root.statusText; textFormat: Text.PlainText; elide: Text.ElideRight; color: root.service && root.service.state === "error" ? Color.urgent : Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        Text { anchors.right: parent.right; anchors.rightMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter; text: root.service && root.service.lastFetchedAt ? "updated " + root.clean(root.service.lastFetchedAt, 30) : ""; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
      }
      Popup {
        id: ignoreMenu
        property int selectedIndex: 0
        readonly property var choices: [
          { label: "one hour", action: "ignore60" },
          { label: "one day", action: "ignore1440" },
          { label: "one week", action: "ignore10080" }
        ]
        function moveChoice(delta) {
          selectedIndex = (selectedIndex + delta + choices.length) % choices.length
        }
        function choose() {
          var action = choices[selectedIndex].action
          close()
          root.confirm(action)
        }
        x: Math.max(Style.space(8), Math.round((parent.width - width) / 2)); y: Math.max(Style.space(70), Math.round((parent.height - height) / 2)); padding: Style.space(8); modal: true; focus: true; popupType: Popup.Item
        onOpened: Qt.callLater(function() { ignoreMenuFocus.forceActiveFocus() })
        onClosed: if (root.opened) root.restoreKeyboardFocus()
        background: Rectangle { color: Color.background; border.width: Style.space(1); border.color: Color.accent }
        contentItem: FocusScope {
          id: ignoreMenuFocus
          implicitWidth: ignoreChoices.implicitWidth
          implicitHeight: ignoreChoices.implicitHeight
          Keys.onPressed: function(event) {
            if (event.text === "j" || event.key === Qt.Key_J || event.key === Qt.Key_Down) root.moveIgnoreMenu(1)
            else if (event.text === "k" || event.key === Qt.Key_K || event.key === Qt.Key_Up) root.moveIgnoreMenu(-1)
            else if (event.key === Qt.Key_Home) ignoreMenu.selectedIndex = 0
            else if (event.key === Qt.Key_End) ignoreMenu.selectedIndex = ignoreMenu.choices.length - 1
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.chooseIgnoreMenu()
            else if (event.key === Qt.Key_Escape) ignoreMenu.close()
            else return
            event.accepted = true
          }
          Column {
            id: ignoreChoices
            spacing: Style.space(5)
            Text { text: "IGNORE FOR"; color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            Text { text: "J/K · ENTER · ESC"; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            Repeater {
              model: ignoreMenu.choices
              delegate: TraceButton {
                required property var modelData
                required property int index
                width: Style.space(180)
                text: modelData.label
                active: ignoreMenu.selectedIndex === index
                onClicked: { ignoreMenu.selectedIndex = index; ignoreMenu.choose() }
              }
            }
          }
        }
      }
      Popup {
        id: projectMenu
        property int selectedIndex: 0
        readonly property var choices: ["all"].concat(root.projectOptions || [])
        function moveChoice(delta) {
          if (choices.length === 0) return
          selectedIndex = (selectedIndex + delta + choices.length) % choices.length
          projectChoices.positionViewAtIndex(selectedIndex, ListView.Contain)
        }
        function choose() {
          var value = choices[Math.max(0, Math.min(selectedIndex, choices.length - 1))]
          root.setProjectFilter(value)
          close()
        }
        x: Math.max(Style.space(8), Math.round((parent.width - width) / 2))
        y: Math.max(Style.space(70), Math.round((parent.height - height) / 2))
        padding: Style.space(8)
        modal: true
        focus: true
        popupType: Popup.Item
        onOpened: Qt.callLater(function() { projectMenuFocus.forceActiveFocus(); projectChoices.positionViewAtIndex(projectMenu.selectedIndex, ListView.Contain) })
        onClosed: if (root.opened) root.restoreKeyboardFocus()
        background: Rectangle { color: Color.background; border.width: Style.space(1); border.color: Color.accent }
        contentItem: FocusScope {
          id: projectMenuFocus
          implicitWidth: projectMenuBody.implicitWidth
          implicitHeight: projectMenuBody.implicitHeight
          Keys.onPressed: function(event) {
            if (event.text === "j" || event.key === Qt.Key_J || event.key === Qt.Key_Down) root.moveProjectMenu(1)
            else if (event.text === "k" || event.key === Qt.Key_K || event.key === Qt.Key_Up) root.moveProjectMenu(-1)
            else if (event.key === Qt.Key_Home) { projectMenu.selectedIndex = 0; projectChoices.positionViewAtBeginning() }
            else if (event.key === Qt.Key_End) { projectMenu.selectedIndex = projectMenu.choices.length - 1; projectChoices.positionViewAtEnd() }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.chooseProjectMenu()
            else if (event.key === Qt.Key_Escape) projectMenu.close()
            else return
            event.accepted = true
          }
          Column {
            id: projectMenuBody
            width: Style.space(230)
            spacing: Style.space(5)
            Text { text: "PROJECT SCOPE"; color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            Text { text: "J/K · ENTER · ESC"; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            ListView {
              id: projectChoices
              width: parent.width
              implicitHeight: Math.min(contentHeight, Style.space(300))
              height: implicitHeight
              clip: true
              spacing: Style.space(5)
              model: projectMenu.choices
              currentIndex: projectMenu.selectedIndex
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
              delegate: TraceButton {
                required property var modelData
                required property int index
                readonly property string value: String(modelData || "all")
                width: ListView.view.width
                text: value === "all" ? "all projects" : root.clean(value, 32)
                compact: true
                active: projectMenu.selectedIndex === index
                onClicked: { projectMenu.selectedIndex = index; projectMenu.choose() }
              }
            }
          }
        }
      }
      Rectangle { anchors.fill: parent; visible: root.pendingAction !== ""; color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, .82); z: 20
        Rectangle { width: Math.min(parent.width - Style.space(40), Style.space(430)); height: confirmBody.implicitHeight + Style.space(32); anchors.centerIn: parent; color: Color.background; border.width: Style.space(1); border.color: root.pendingAction === "disconnect" ? Color.urgent : Color.accent
          Column {
            id: confirmBody; anchors.fill: parent; anchors.margins: Style.space(16); spacing: Style.space(12)
            Text { width: parent.width; text: root.actionLabel(root.pendingAction); wrapMode: Text.WordWrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title }
            Text { width: parent.width; text: root.actionDescription(root.pendingAction); textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            Row {
              spacing: Style.space(7)
              TraceButton { text: "confirm [Enter]"; danger: root.pendingAction === "disconnect"; onClicked: root.runPending() }
              TraceButton { text: "cancel [Esc]"; onClicked: root.pendingAction = "" }
            }
          }
        }
      }
      ShortcutHelp { visible: root.helpVisible; z: 30; onDismissed: root.helpVisible = false }
    }
  }
}
