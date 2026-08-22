import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "wbarakat.trace"

  readonly property var trace: bar && bar.shell ? bar.shell.serviceFor("wbarakat.trace") : null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property int attentionCount: trace ? Math.max(Number(trace.unreadCount || 0), Number(trace.regressionCount || 0)) : 0
  readonly property bool failed: trace && trace.state === "error"

  function pushSettings() {
    if (trace && typeof trace.applySettings === "function") trace.applySettings(settings)
  }

  function summon() {
    if (bar && bar.shell && typeof bar.shell.toggle === "function")
      bar.shell.toggle("wbarakat.trace", "{}")
  }

  onSettingsChanged: pushSettings()
  onTraceChanged: pushSettings()
  Component.onCompleted: pushSettings()

  implicitWidth: icon.implicitWidth
  implicitHeight: icon.implicitHeight

  BarIconButton {
    id: icon
    anchors.fill: parent
    bar: root.bar
    tooltipText: !root.trace ? "Trace" : (root.failed ? "Trace · " + root.trace.message
      : root.attentionCount > 0 ? "Trace · " + root.attentionCount + " needs attention" : "Trace · quiet")
    active: root.failed || root.attentionCount > 0
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: "!"
          color: root.failed ? Color.urgent : (root.trace && root.trace.ready ? root.foreground : Color.muted)
          font.family: Style.font.family
          font.bold: true
          font.pixelSize: Style.font.body
        }
        Rectangle {
          visible: !root.failed && root.attentionCount > 0
          anchors.right: parent.right
          anchors.top: parent.top
          width: Style.space(5)
          height: width
          color: root.attentionCount > 0 ? Color.accent : "transparent"
        }
        Rectangle {
          visible: root.failed
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          width: Style.space(12)
          height: Style.space(1)
          color: Color.urgent
        }
      }
    }
    onPressed: function(button) { if (button === Qt.LeftButton) root.summon() }
  }
}
