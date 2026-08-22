import QtQuick
import QtQuick.Controls
import qs.Commons

Item {
  id: root
  property var issue: null
  property var detail: null
  property bool loading: false
  signal resolveRequested()
  signal assignRequested()
  signal reviewRequested()
  signal explainRequested()
  signal ignoreRequested()
  signal openRequested()
  signal copyRequested()
  function clean(value, limit) {
    var text = String(value === undefined || value === null ? "" : value).replace(/[\u0000-\u001f\u007f]/g, " ")
    return text.length > limit ? text.slice(0, limit - 1) + "…" : text
  }
  function val(name) { return detail && detail[name] !== undefined ? detail[name] : (issue ? issue[name] : "") }

  Rectangle { anchors.fill: parent; color: Color.background; border.width: Style.space(1); border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, .18) }
  Flickable {
    anchors.fill: parent; anchors.margins: Style.space(14); clip: true
    contentWidth: width; contentHeight: body.implicitHeight
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    Column {
      id: body; width: parent.width; spacing: Style.space(12)
      Text { width: parent.width; text: root.clean(root.val("title") || "Select an issue", 300); textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true }
      Flow { width: parent.width; spacing: Style.space(6)
        Repeater { model: [root.clean(root.val("shortId"), 30), root.clean(root.val("project"), 32), root.val("isRegression") ? "REGRESSION" : ""]
          delegate: Rectangle { visible: modelData !== ""; height: tag.implicitHeight + Style.space(6); width: tag.implicitWidth + Style.space(10); color: modelData === "REGRESSION" ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, .16) : Style.normalFillFor(Color.foreground, Color.accent); Text { id: tag; anchors.centerIn: parent; text: modelData; textFormat: Text.PlainText; color: modelData === "REGRESSION" ? Color.urgent : Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall } }
        }
      }
      Grid { columns: 2; columnSpacing: Style.space(22); rowSpacing: Style.space(5)
        Repeater { model: [["CULPRIT", root.clean(root.val("culprit"), 140)], ["ENVIRONMENT", root.clean(root.val("environment"), 50)], ["EVENTS", String(root.val("count") || 0)], ["USERS", String(root.val("userCount") || 0)], ["ASSIGNEE", root.clean(root.val("assignedTo"), 50)]]
          delegate: Row {
            spacing: Style.space(7)
            Text { text: modelData[0]; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            Text { text: modelData[1] || "—"; textFormat: Text.PlainText; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
          }
        }
      }
      Text { visible: root.detail && root.detail.tags && root.detail.tags.length > 0; text: "TAGS"; color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
      Flow {
        visible: root.detail && root.detail.tags && root.detail.tags.length > 0
        width: parent.width; spacing: Style.space(5)
        Repeater {
          model: root.detail && root.detail.tags ? root.detail.tags : []
          delegate: Rectangle {
            required property var modelData
            width: detailTag.implicitWidth + Style.space(10); height: detailTag.implicitHeight + Style.space(6)
            color: Style.normalFillFor(Color.foreground, Color.accent)
            Text { id: detailTag; anchors.centerIn: parent; text: root.clean((modelData.key ? modelData.key + ":" : "") + modelData.value, 90); textFormat: Text.PlainText; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
          }
        }
      }
      Flow { width: parent.width; spacing: Style.space(6)
        TraceButton { text: "resolve [e]"; onClicked: root.resolveRequested() }
        TraceButton { text: "assign [a]"; onClicked: root.assignRequested() }
        TraceButton { text: "review [x]"; onClicked: root.reviewRequested() }
        TraceButton { text: "ignore [z]"; onClicked: root.ignoreRequested() }
        TraceButton { text: "explain [i]"; onClicked: root.explainRequested() }
        TraceButton { text: "open [o]"; onClicked: root.openRequested() }
        TraceButton { text: "copy [y]"; onClicked: root.copyRequested() }
      }
      Rectangle { width: parent.width; height: Style.space(1); color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, .18) }
      Text { text: "STACK TRACE"; color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
      Repeater {
        model: root.detail && root.detail.stacktrace ? root.detail.stacktrace : []
        delegate: Rectangle {
          required property var modelData
          width: body.width; height: frame.implicitHeight + Style.space(14)
          color: modelData.inApp ? Style.selectedFillFor(Color.foreground, Color.accent) : Style.normalFillFor(Color.foreground, Color.accent)
          Column { id: frame; anchors.fill: parent; anchors.margins: Style.space(7); spacing: Style.space(3)
            Text { text: root.clean(modelData.function || modelData.module || "<anonymous>", 180); textFormat: Text.PlainText; color: modelData.inApp ? Color.accent : Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; font.bold: modelData.inApp }
            Text { text: root.clean(modelData.filename || "", 220) + (modelData.line ? ":" + modelData.line : ""); textFormat: Text.PlainText; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            Text { visible: modelData.context !== undefined && String(modelData.context) !== ""; width: parent.width; text: root.clean(modelData.context, 500); textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
          }
        }
      }
      Text { visible: !root.loading && (!root.detail || !root.detail.stacktrace || root.detail.stacktrace.length === 0); text: "No stack trace was returned for this issue."; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.body }
      Text { visible: root.detail && root.detail.breadcrumbs && root.detail.breadcrumbs.length > 0; text: "BREADCRUMBS"; color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
      Repeater {
        model: root.detail && root.detail.breadcrumbs ? root.detail.breadcrumbs : []
        delegate: Row {
          required property var modelData
          width: body.width; spacing: Style.space(8)
          Text { width: Style.space(90); text: root.clean(modelData.category || modelData.level || "event", 20).toUpperCase(); textFormat: Text.PlainText; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
          Text { width: parent.width - Style.space(98); text: root.clean(modelData.message || "", 300); textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        }
      }
    }
  }
  BusyIndicator { anchors.centerIn: parent; running: root.loading; visible: running }
}
