import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
  id: root
  property var service: null
  signal backRequested()
  signal demoRequested()
  signal disconnectRequested()
  function clean(value, limit) { var x = String(value || "").replace(/[\u0000-\u001f\u007f]/g, " "); return x.length > limit ? x.slice(0, limit - 1) + "…" : x }

  Rectangle { anchors.fill: parent; color: Color.background }
  Column {
    width: Math.min(parent.width - Style.space(40), Style.space(650)); anchors.centerIn: parent; spacing: Style.space(15)
    Text { text: "SETTINGS"; color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
    Text { text: "Trace connection"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.display; font.bold: true }
    Rectangle { width: parent.width; height: connection.implicitHeight + Style.space(20); color: Style.normalFillFor(Color.foreground, Color.accent); border.width: Style.space(1); border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, .18)
      Column { id: connection; anchors.fill: parent; anchors.margins: Style.space(10); spacing: Style.space(5)
        Text { text: root.service && root.service.demoMode ? "DEMO MODE" : (root.service && root.service.configured ? "CONNECTED" : "NOT CONNECTED"); color: root.service && root.service.demoMode ? Color.accent : (root.service && root.service.configured ? Color.foreground : Color.urgent); font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        Text { text: root.service && root.service.demoMode ? "Realistic local fixtures · no credentials" : "Credentials are stored only in GNOME Keyring."; width: parent.width; wrapMode: Text.WordWrap; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.body }
      }
    }
    Row { spacing: Style.space(8)
      TraceButton { text: root.service && root.service.demoMode ? "leave demo" : "use demo"; onClicked: root.demoRequested() }
      TraceButton { text: "disconnect"; danger: true; visible: root.service && root.service.configured && !root.service.demoMode; onClicked: root.disconnectRequested() }
      TraceButton { text: "back"; onClicked: root.backRequested() }
    }
    Text { text: "Refresh and issue limits are available in Omarchy’s widget settings. Token changes require reconnecting."; width: parent.width; wrapMode: Text.WordWrap; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
  }
}
