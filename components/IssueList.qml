import QtQuick
import QtQuick.Controls
import qs.Commons

Item {
  id: root
  property var issues: []
  property var selectedIssue: null
  property bool loading: false
  property string query: ""
  signal selected(int index)
  signal activated(var issue)

  function clean(value, limit) {
    var text = String(value === undefined || value === null ? "" : value).replace(/[\u0000-\u001f\u007f]/g, " ")
    return text.length > limit ? text.slice(0, limit - 1) + "…" : text
  }
  function level(issue) { return clean(issue && issue.level ? issue.level : "error", 12).toUpperCase() }
  function priority(issue) {
    var value = issue && issue.priority ? clean(issue.priority, 12).toUpperCase() : ""
    if (value !== "") return value
    if (issue && String(issue.level || "").toLowerCase() === "fatal") return "HIGH"
    if (issue && issue.isUnhandled) return "UNHANDLED"
    return ""
  }
  function needsAttention(issue) {
    return !!issue && (issue.isRegression || issue.inInbox === true || issue.hasSeen === false
      || String(issue.substatus || "").toLowerCase() === "new")
  }
  function attentionLabel(issue) {
    if (!issue || issue.isRegression) return ""
    return needsAttention(issue) ? "UNREVIEWED" : ""
  }
  function shortTime(value) {
    var date = new Date(String(value || "")); if (isNaN(date.getTime())) return ""
    var hours = Math.floor((Date.now() - date.getTime()) / 3600000)
    return hours < 1 ? "now" : (hours < 24 ? hours + "h" : Math.floor(hours / 24) + "d")
  }

  Rectangle {
    anchors.fill: parent
    color: Color.background
    border.width: Style.space(1)
    border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.18)
  }
  ListView {
    id: list
    anchors.fill: parent
    anchors.margins: Style.space(4)
    clip: true
    model: root.issues || []
    spacing: Style.space(2)
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    delegate: Rectangle {
      required property var modelData
      required property int index
      width: list.width
      height: Style.space(76)
      readonly property bool current: root.selectedIssue && String(root.selectedIssue.id) === String(modelData.id)
      color: current ? Style.selectedFillFor(Color.foreground, Color.accent) : (hover.hovered ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent")
      border.width: current ? Style.space(1) : 0
      border.color: current ? Color.accent : "transparent"

      Rectangle {
        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
        width: Style.space(3)
        color: modelData.isRegression ? Color.urgent : (root.needsAttention(modelData)
          ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, .28))
      }
      Column {
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.margins: Style.space(9); anchors.leftMargin: Style.space(12)
        spacing: Style.space(3)
        Item {
          width: parent.width; height: Math.max(issueMeta.implicitHeight, seenAt.implicitHeight)
          Row {
            id: issueMeta; anchors.left: parent.left; spacing: Style.space(7)
            Text { text: root.clean(modelData.project || "unknown", 22).toUpperCase(); textFormat: Text.PlainText; color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            Text { text: root.level(modelData); textFormat: Text.PlainText; color: modelData.isRegression ? Color.urgent : Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            Text { text: modelData.isRegression ? "REGRESSION" : ""; visible: text !== ""; color: Color.urgent; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            Text { text: root.attentionLabel(modelData); visible: text !== ""; color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            Text { text: root.priority(modelData); textFormat: Text.PlainText; visible: text !== ""; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
          }
          Text { id: seenAt; anchors.right: parent.right; text: root.shortTime(modelData.lastSeen); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        }
        Text { width: parent.width; text: root.clean(modelData.title || "Untitled issue", 160); textFormat: Text.PlainText; elide: Text.ElideRight; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: current }
        Row { spacing: Style.space(8)
          Text { text: root.clean(modelData.culprit || "No culprit", 55); textFormat: Text.PlainText; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight; width: Math.min(Style.space(210), implicitWidth) }
          Text { text: String(Number(modelData.count || 0)) + " events"; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
          Text { text: String(Number(modelData.userCount || 0)) + " users"; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        }
      }
      HoverHandler { id: hover }
      TapHandler { onTapped: { root.selected(index); root.activated(modelData) } }
    }
    Text {
      anchors.centerIn: parent
      visible: !root.loading && list.count === 0
      text: root.query !== "" ? "No matching issues" : "Nothing needs your attention."
      color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.body
    }
    BusyIndicator { anchors.centerIn: parent; running: root.loading; visible: running }
  }
}
