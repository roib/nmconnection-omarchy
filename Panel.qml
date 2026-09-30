import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// NetworkManager status widget. The bar icon answers "is a VPN up?"; the
// popup lists VPN profiles and active connections with details and toggles.
// All data comes from the sibling `nm-status` script as one JSON document.
Panel {
  id: root
  moduleName: "local.nmstatus"
  ipcTarget: "local.nmstatus"

  property var nm: null
  property bool initialLoad: true
  // uuid -> epoch seconds the connection was first seen active (0 = unknown).
  property var since: ({})
  property real nowSec: Date.now() / 1000
  property bool refreshPending: false

  property string busyUuid: ""
  property string errorUuid: ""
  property string errorText: ""
  property string copiedValue: ""

  property int cursorIndex: -1
  property bool cursorActive: false

  readonly property string scriptPath: decodeURIComponent(String(Qt.resolvedUrl("nm-status")).replace(/^file:\/\//, ""))
  readonly property var vpnList: Model.vpnProfiles(nm)
  readonly property var otherList: Model.otherConnections(nm)
  readonly property var rows: vpnList.concat(otherList)
  readonly property bool vpnUp: Model.activeVpns(nm).length > 0
  // Theme green from the active Omarchy theme; the shell's Color singleton
  // doesn't expose the terminal palette.
  property color green: "#a6e3a1"
  readonly property color iconColor: vpnUp ? green : (bar ? bar.barForeground : Color.foreground)
  readonly property int intervalMs: Math.max(2, Number(setting("refreshIntervalSec", 10))) * 1000

  readonly property string glyphOn: String.fromCodePoint(0xF0565)   // md shield-check
  readonly property string glyphOff: String.fromCodePoint(0xF099E)  // md shield-off-outline

  function refresh() {
    themeColors.reload()
    if (statusProc.running) { refreshPending = true; return }
    statusProc.running = true
  }

  function apply(text) {
    var parsed = Model.parse(text)
    if (!parsed) return
    nowSec = Date.now() / 1000
    since = Model.updateSince(since, parsed, nowSec, initialLoad)
    initialLoad = false
    nm = parsed
    if (cursorIndex >= rows.length) cursorIndex = rows.length - 1
  }

  function uptimeFor(p) {
    var start = since[p.uuid]
    return start > 0 ? Model.formatUptime(nowSec - start) : ""
  }

  function runAction(uuid, command) {
    if (actionProc.running) return
    busyUuid = uuid
    errorUuid = ""
    actionProc.command = command
    actionProc.running = true
  }

  function toggleConnection(p) {
    runAction(p.uuid, ["nmcli", "connection", p.active ? "down" : "up", "uuid", p.uuid])
  }

  function toggleAutoconnect(p) {
    runAction(p.uuid, ["nmcli", "connection", "modify", "uuid", p.uuid,
                       "connection.autoconnect", p.autoconnect ? "no" : "yes"])
  }

  function copy(value) {
    var v = Model.stripPrefix(value)
    if (!v) return
    Quickshell.execDetached(["wl-copy", v])
    copiedValue = value
    copiedTimer.restart()
  }

  function openEditor() {
    Quickshell.execDetached(["nm-connection-editor"])
    close()
  }

  // Scroll the popup so `item` is fully visible.
  function ensureVisible(item) {
    var flick = scrollArea.contentItem
    if (!item || !flick || flick.contentY === undefined) return
    var top = item.mapToItem(flick.contentItem, 0, 0).y
    var bottom = top + item.height
    var margin = Style.space(6)
    if (top - margin < flick.contentY) flick.contentY = Math.max(0, top - margin)
    else if (bottom + margin > flick.contentY + flick.height)
      flick.contentY = Math.min(flick.contentHeight - flick.height, bottom + margin - flick.height)
  }

  function moveCursor(delta) {
    if (rows.length === 0) return
    if (!cursorActive || cursorIndex < 0) { cursorActive = true; cursorIndex = 0; return }
    cursorIndex = Math.max(0, Math.min(rows.length - 1, cursorIndex + delta))
  }

  onOpenedChanged: {
    if (opened) refresh()
    else { cursorActive = false; cursorIndex = -1 }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FileView {
    id: themeColors
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    printErrors: false
    onLoaded: {
      var m = text().match(/^\s*green\s*=\s*"(#[0-9a-fA-F]{6,8})"/m)
      if (m) root.green = m[1]
    }
  }

  Process {
    id: statusProc
    command: ["bash", root.scriptPath]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.apply(text) }
    onExited: if (root.refreshPending) { root.refreshPending = false; root.refresh() }
  }

  // Push-style updates: any NetworkManager event triggers a debounced refresh.
  Process {
    id: monitorProc
    command: ["nmcli", "monitor"]
    running: true
    stdout: SplitParser { onRead: debounce.restart() }
    onExited: monitorRestart.restart()
  }

  Timer { id: debounce; interval: 300; onTriggered: root.refresh() }
  Timer { id: monitorRestart; interval: 5000; onTriggered: monitorProc.running = true }

  Timer {
    interval: root.opened ? 2000 : root.intervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: actionProc
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var lines = actionErr.text.trim().split("\n")
        root.errorText = (lines[lines.length - 1] || "Command failed").replace(/^Error:\s*/, "")
        root.errorUuid = root.busyUuid
        errorTimer.restart()
      }
      root.busyUuid = ""
      root.refresh()
    }
  }

  Timer { id: errorTimer; interval: 5000; onTriggered: { root.errorUuid = ""; root.errorText = "" } }
  Timer { id: copiedTimer; interval: 1500; onTriggered: root.copiedValue = "" }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vpnUp ? root.glyphOn : root.glyphOff
    foreground: root.iconColor
    tooltipText: root.opened ? "" : Model.summary(root.nm)
    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dy !== 0 ? dy : dx) }
      onActivateRequested: {
        if (root.cursorActive && root.cursorIndex >= 0 && root.cursorIndex < root.rows.length)
          root.toggleConnection(root.rows[root.cursorIndex])
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: column.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: column.implicitHeight > scrollArea.height
        }

        Column {
          id: column
          width: scrollArea.availableWidth
          spacing: Style.space(12)

          // ---------- Hero: shield · VPN status · connectivity badge ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: root.vpnUp ? root.glyphOn : root.glyphOff
              color: root.vpnUp ? root.green : root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: badge.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                text: "Network"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                elide: Text.ElideRight
                text: {
                  var v = Model.activeVpns(root.nm)
                  return (v.length ? "VPN · " + v.map(function(p) { return p.name }).join(", ") : "VPN off").toUpperCase()
                }
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }
            }

            Rectangle {
              id: badge
              visible: Model.connectivityLabel(root.nm) !== ""
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              radius: Style.cornerRadius > 0 ? height / 2 : 0
              width: badgeText.implicitWidth + Style.space(14)
              height: badgeText.implicitHeight + Style.space(6)
              color: "transparent"
              border.width: 1
              border.color: Model.connectivityOk(root.nm) ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.35) : root.bar.urgent

              Text {
                id: badgeText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: Model.connectivityLabel(root.nm).toUpperCase()
                color: Model.connectivityOk(root.nm) ? root.bar.foreground : root.bar.urgent
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }
            }
          }

          // ---------- DNS ----------
          Column {
            width: parent.width
            spacing: Style.spacing.labelGap
            visible: root.nm !== null

            InfoPair {
              label: "DNS"
              value: Model.defaultDns(root.nm).map(function(l) { return l.server + " (" + l.link + ")" }).join(", ") || "—"
            }

            Text {
              visible: Model.dnsLeaks(root.nm)
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: "⚠ DNS queries can go outside the VPN"
              color: root.bar.urgent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- VPN profiles ----------
          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "VPN"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Repeater {
              model: root.vpnList
              ConnectionRow {
                required property var modelData
                required property int index
                profile: modelData
                rowIndex: index
              }
            }

            EmptyText { visible: root.nm !== null && root.vpnList.length === 0; text: "No VPN profiles" }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Other active connections ----------
          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "CONNECTIONS"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Repeater {
              model: root.otherList
              ConnectionRow {
                required property var modelData
                required property int index
                profile: modelData
                rowIndex: root.vpnList.length + index
              }
            }

            EmptyText { visible: root.nm !== null && root.otherList.length === 0; text: "No active connections" }
          }

          Button {
            visible: root.nm !== null && root.nm.editor === true
            width: parent.width
            text: "Open connection editor"
            iconText: String.fromCodePoint(0xF0493)
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: root.openEditor()
          }
        }
      }
    }
  }

  // One connection: title line with up/down switch, then details.
  component ConnectionRow: Column {
    id: row
    property var profile: ({})
    property int rowIndex: -1
    readonly property bool isVpn: Model.isVpn(profile)
    readonly property bool busy: root.busyUuid === profile.uuid

    width: parent ? parent.width : 0
    spacing: Style.spacing.labelGap

    readonly property bool hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureVisible(row)

    Item {
      width: parent.width
      implicitHeight: Math.max(titleCol.implicitHeight, upSwitch.implicitHeight)

      Column {
        id: titleCol
        anchors.left: parent.left
        anchors.right: autoChip.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
          width: parent.width
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: row.profile.name
          color: root.bar.foreground
          opacity: row.profile.active ? 1 : 0.7
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: row.profile.active
        }

        Text {
          width: parent.width
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: {
            var p = row.profile
            var parts = [Model.typeLabel(p)]
            if (p.device) parts.push(p.device)
            if (row.busy) parts.push(p.active ? "disconnecting…" : "connecting…")
            else if (!p.active) {
              parts.push("off")
              if (p.fullTunnel !== undefined) parts.push(p.fullTunnel ? "full" : "split")
              if (p.endpoint) parts.push(p.endpoint)
            }
            return parts.join(" · ")
          }
          color: root.bar.foreground
          opacity: 0.55
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Button {
        id: autoChip
        anchors.right: upSwitch.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: "auto"
        fontSize: Style.font.caption
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        horizontalPadding: Style.space(6)
        verticalPadding: Style.space(2)
        bordered: true
        active: row.profile.autoconnect === true
        opacity: row.profile.autoconnect ? 1 : 0.45
        tooltipText: row.profile.autoconnect ? "Autoconnect on — click to disable" : "Autoconnect off — click to enable"
        onClicked: if (!row.busy) root.toggleAutoconnect(row.profile)
      }

      ToggleSwitch {
        id: upSwitch
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: row.profile.active === true
        busy: row.busy
        foreground: root.bar.foreground
        hasCursor: row.hasCursor
        onToggled: root.toggleConnection(row.profile)
        onHovered: function(h) { if (h) { root.cursorActive = true; root.cursorIndex = row.rowIndex } }
      }
    }

    Column {
      visible: !!row.profile.active
      width: parent.width
      spacing: Style.spacing.labelGap
      leftPadding: Style.space(8)

      Repeater {
        model: row.profile.active ? (row.profile.ip4 || []).concat(row.profile.ip6 || []) : []
        CopyPair {
          required property var modelData
          label: "Address"
          value: modelData
        }
      }
      InfoPair { visible: !!row.profile.active && !!row.profile.gateway; label: "Gateway"; value: row.profile.gateway || "" }
      InfoPair {
        visible: !!row.profile.active && (row.profile.dns || []).length > 0
        label: "DNS"
        value: (row.profile.dns || []).join(", ")
      }
      InfoPair {
        visible: row.profile.ssid !== undefined && row.profile.ssid !== null
        label: "Signal"
        value: (row.profile.signal !== null && row.profile.signal !== undefined ? row.profile.signal + "%" : "—") + (row.profile.freq ? " · " + row.profile.freq : "")
      }
      InfoPair {
        visible: row.profile.speed !== undefined && row.profile.speed !== null
        label: "Link speed"
        value: row.profile.speed + " Mb/s"
      }
      CopyPair { visible: !!row.profile.endpoint; label: "Endpoint"; value: row.profile.endpoint || "" }
      InfoPair {
        visible: row.isVpn && (row.profile.fullTunnel !== undefined || row.profile.routes !== undefined)
        label: "Routing"
        value: row.profile.fullTunnel ? "Full tunnel · all traffic" : "Split tunnel · listed IPs only"
      }
      Repeater {
        model: row.isVpn ? Model.routeRows(row.profile) : []
        CopyPair {
          required property var modelData
          label: modelData.label
          value: modelData.value
          suffix: modelData.hint
          copyable: !modelData.more
          tooltip: modelData.more ? modelData.all : ""
        }
      }
      InfoPair { visible: root.uptimeFor(row.profile) !== ""; label: "Up for"; value: root.uptimeFor(row.profile) }
      InfoPair {
        visible: !!row.profile.active && row.profile.rx !== undefined
        label: "Traffic"
        value: "↓ " + Model.formatBytes(row.profile.rx) + "   ↑ " + Model.formatBytes(row.profile.tx)
      }

    }

    Text {
      visible: root.errorUuid !== "" && root.errorUuid === row.profile.uuid
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.errorText
      color: root.bar.urgent
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component InfoPair: Item {
    property string label: ""
    property string value: ""
    property string displayValue: value
    property alias valueItem: valueText

    width: parent ? parent.width - (parent.leftPadding || 0) : 0
    implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)

    InfoLabel { id: labelText; text: label; anchors.left: parent.left; anchors.top: parent.top }
    InfoValue {
      id: valueText
      text: displayValue
      anchors.right: parent.right
      anchors.top: parent.top
      width: Math.min(implicitWidth, parent.width - labelText.implicitWidth - Style.space(12))
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideMiddle
    }
  }

  // InfoPair whose value copies to the clipboard on click.
  component CopyPair: InfoPair {
    id: copyPair
    property string suffix: ""
    property bool copyable: true
    property string tooltip: ""
    displayValue: root.copiedValue !== "" && root.copiedValue === value
      ? "Copied"
      : value + (suffix ? "  (" + suffix + ")" : "")

    MouseArea {
      id: copyMouse
      anchors.fill: copyPair.valueItem
      hoverEnabled: true
      cursorShape: copyPair.copyable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (copyPair.copyable) root.copy(copyPair.value)
    }

    Binding { target: copyPair.valueItem; property: "font.underline"; value: copyPair.copyable && copyMouse.containsMouse }

    PanelToolTip {
      visible: copyPair.tooltip !== "" && copyMouse.containsMouse
      text: copyPair.tooltip
    }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component EmptyText: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.5
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
