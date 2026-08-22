import QtQuick
import qs.Commons
import qs.Ui

Button {
  id: root
  property bool danger: false
  property bool compact: false
  foreground: danger ? Color.urgent : Color.foreground
  accent: danger ? Color.urgent : Color.accent
  fontFamily: Style.font.family
  fontSize: Style.font.bodySmall
  horizontalPadding: Style.space(compact ? 6 : 9)
  verticalPadding: Style.space(compact ? 3 : 5)
  bordered: true
}
