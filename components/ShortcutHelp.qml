import QtQuick
import qs.Commons
import qs.Ui

Rectangle {
  id: root
  anchors.fill: parent
  color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, .92)
  signal dismissed()
  focus: true
  Keys.onPressed: function(event) { event.accepted = true; root.dismissed() }
  Rectangle {
    width: Math.min(parent.width - Style.space(40), Style.space(540)); height: content.implicitHeight + Style.space(32); anchors.centerIn: parent
    color: Color.background; border.width: Style.space(1); border.color: Color.accent
    Column { id: content; anchors.fill: parent; anchors.margins: Style.space(16); spacing: Style.space(7)
      Text { text: "TRACE SHORTCUTS"; color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
      Repeater { model: [["j / k · ↑ / ↓", "move selection or popup choice"], ["Enter", "open, choose, or confirm"], ["Esc", "cancel, back, then close"], ["e · a · x · z", "resolve · assign · review · timed ignore"], ["o · y", "open in Sentry · copy permalink"], ["/ · Ctrl+K", "search"], ["p", "choose project scope"], ["g r · g u", "regressions · unresolved"], ["F5", "refresh"]]
        delegate: Row {
          width: parent.width
          Text { text: modelData[0]; width: Style.space(165); color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
          Text { text: modelData[1]; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
        }
      }
      TraceButton { text: "close [?]"; onClicked: root.dismissed() }
    }
  }
  MouseArea { anchors.fill: parent; z: -1; onClicked: root.dismissed() }
}
