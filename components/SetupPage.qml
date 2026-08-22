import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
  id: root
  property var service: null
  signal saved()
  signal demoRequested()
  function clean(value, limit) { var x = String(value || "").replace(/[\u0000-\u001f\u007f]/g, " "); return x.length > limit ? x.slice(0, limit - 1) + "…" : x }

  Rectangle { anchors.fill: parent; color: Color.background }
  Flickable {
    anchors.fill: parent; contentWidth: width; contentHeight: card.implicitHeight + Style.space(48); clip: true
    Column {
      id: card; width: Math.min(parent.width - Style.space(40), Style.space(610)); anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.topMargin: Style.space(36); spacing: Style.space(13)
      Text { text: "TRACE"; color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
      Text { text: "Production errors, without another browser tab."; width: parent.width; wrapMode: Text.WordWrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.display; font.bold: true }
      Text { text: "Connect a Sentry organization. Your token is sent to GNOME Keyring and is never written to Trace configuration."; width: parent.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.body }
      Text { text: "SENTRY BASE URL"; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
      TextField { id: baseUrl; width: parent.width; text: "https://sentry.io"; placeholderText: "https://sentry.io" }
      Text { text: "ORGANIZATION SLUG"; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
      TextField { id: organization; width: parent.width; placeholderText: "my-organization" }
      Text { text: "PROJECT SLUGS · OPTIONAL"; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
      TextField { id: projects; width: parent.width; placeholderText: "api, web, worker" }
      Text { text: "ENVIRONMENTS · OPTIONAL"; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
      TextField { id: environments; width: parent.width; text: "production"; placeholderText: "production" }
      Text { text: "Use comma-separated environments. Leave blank to include every environment."; width: parent.width; wrapMode: Text.WordWrap; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
      Text { text: "AUTH TOKEN"; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
      TextField { id: token; width: parent.width; password: true; placeholderText: "Sentry API token" }
      Text { visible: root.service && root.service.message !== ""; width: parent.width; text: root.clean(root.service.message, 320); textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: root.service && root.service.state === "error" ? Color.urgent : Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
      Row { spacing: Style.space(8)
        TraceButton { text: "connect"; enabled: organization.text.trim() !== "" && token.text !== ""; onClicked: { root.service.saveSetup({ baseUrl: baseUrl.text.trim(), organization: organization.text.trim(), projects: projects.text.trim(), environments: environments.text.trim(), token: token.text }); token.text = ""; root.saved() } }
        TraceButton { text: "try demo"; onClicked: root.demoRequested() }
      }
      Text { text: "Demo mode uses the same inbox and triage path, with local realistic issues."; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
    }
  }
}
