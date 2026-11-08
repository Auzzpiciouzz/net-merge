import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "net-merge"
  ipcTarget: "net-merge"
  manageIpc: false

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string glyph: "󰘬"
  readonly property string barLabelMode: String(setting("barLabel", "Icon only"))
  readonly property bool hideWhenOff: setting("hideWhenOff", false) === true

  // Keyboard cursor: 0 = on/off switch, 1..n = adapter caps, n+1 = autostart.
  property bool cursorActive: false
  property int cursorIndex: 0
  readonly property int adapterCount: nm.adapters.length
  readonly property int lastIndex: adapterCount + 1

  readonly property string barLabel: {
    if (barLabelMode !== "Combined speed" || !nm.on || (bar && bar.vertical)) return ""
    return Model.formatRate(nm.totals.down, Commons.I18n.formatNumber)
  }

  readonly property string heroMeta: {
    if (!nm.loaded) return strings.t("status.checking")
    if (!nm.installed) return strings.t("status.missing")
    if (nm.on) {
      var n = nm.totals.live
      var merging = strings.tn("status.merging", n).arg(Commons.I18n.formatNumber(n))
      return nm.uptime !== "" ? strings.t("status.mergingFor").arg(merging).arg(nm.uptime) : merging
    }
    if (nm.state !== "off" && nm.state !== "unknown") return nm.headline
    return nm.trayRunning ? strings.t("status.off") : strings.t("status.trayStopped")
  }

  readonly property string errorText: {
    var e = nm.lastError
    if (e === "") return ""
    if (e === "@timeout") return strings.t("error.timeout")
    if (e === "@failed") return strings.t("error.failed")
    return e
  }

  function toggleMerging() {
    if (nm.installed && !nm.busy) nm.toggle()
  }

  function moveCursor(dy) {
    if (!cursorActive) { cursorActive = true; return }
    cursorIndex = Math.max(0, Math.min(lastIndex, cursorIndex + dy))
  }

  function activateCursor() {
    if (cursorIndex === 0) toggleMerging()
    else if (cursorIndex === lastIndex) nm.setAutostart(!nm.autostart)
    else {
      var row = adapterColumn.children[cursorIndex - 1]
      if (row && row.focusCap) row.focusCap()
    }
  }

  visible: !(hideWhenOff && nm.loaded && !nm.on)
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    nm.fast = opened
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
    }
  }

  Service {
    id: nm
    settings: root.settings
  }

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function on(): string { nm.turnOn(); return "ok" }
    function off(): string { nm.turnOff(); return "ok" }
    function toggleMerging(): string { root.toggleMerging(); return "ok" }
    function status(): string { return nm.headline !== "" ? nm.headline : nm.state }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    labelText: root.barLabel
    slotSize: Style.bar.iconSlot * (root.barLabel !== "" ? 3.4 : 1)
    dimmed: !nm.on
    tooltipText: ""
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleMerging()
      else if (b === Qt.MiddleButton) nm.refresh(true)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(600))

    content: PanelKeyCatcher {
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T" || t === " ") root.toggleMerging()
        else if (t === "r" || t === "R") nm.refresh(true)
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "net-merge"
            meta: root.heroMeta
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: nm.on ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: root.glyph
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              ToggleSwitch {
                id: power
                visible: nm.installed
                checked: nm.on
                busy: nm.busy
                hasCursor: root.cursorActive && root.cursorIndex === 0
                foreground: root.foreground
                onHovered: function(on) { if (on) { root.cursorActive = true; root.cursorIndex = 0 } }
                onToggled: root.toggleMerging()

                PanelToolTip {
                  visible: power.containsMouse
                  text: nm.on ? strings.t("action.turnOff") : strings.t("action.turnOn")
                  fontFamily: root.fontFamily
                }
              }
            }
          }

          Caption {
            visible: root.errorText !== ""
            text: root.errorText
            color: root.urgent
          }

          Caption {
            visible: nm.installed && nm.loaded && !nm.on && !nm.trayRunning && root.errorText === ""
            text: strings.t("hint.trayStart")
          }

          Caption {
            visible: !nm.installed
            text: strings.t("hint.install")
          }

          // Combined throughput while merging.
          Row {
            visible: nm.on && nm.totals.live > 0
            width: parent.width
            spacing: Style.space(8)

            Stat { width: (parent.width - parent.spacing * 2) / 3; label: strings.t("stat.down"); value: Model.formatRate(nm.totals.down, Commons.I18n.formatNumber) }
            Stat { width: (parent.width - parent.spacing * 2) / 3; label: strings.t("stat.up"); value: Model.formatRate(nm.totals.up, Commons.I18n.formatNumber) }
            Stat {
              width: (parent.width - parent.spacing * 2) / 3
              label: strings.t("stat.connections")
              value: Commons.I18n.formatNumber(nm.totals.active)
            }
          }

          PanelSeparator { visible: nm.installed && root.adapterCount > 0; foreground: root.foreground }

          Column {
            visible: nm.installed && root.adapterCount > 0
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: strings.t("section.adapters")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: adapterColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: nm.adapters
                AdapterRow {
                  required property var modelData
                  required property int index
                  width: adapterColumn.width
                  adapter: modelData
                  rowIndex: index
                }
              }
            }

            Caption {
              visible: nm.ipv6 !== "" && nm.on
              text: strings.t("ipv6").arg(nm.ipv6)
            }
          }

          PanelSeparator { visible: nm.installed; foreground: root.foreground }

          Toggle {
            visible: nm.installed
            width: parent.width
            label: strings.t("autostart.label")
            description: strings.t("autostart.description")
            checked: nm.autostart
            hasCursor: root.cursorActive && root.cursorIndex === root.lastIndex
            foreground: root.foreground
            fontFamily: root.fontFamily
            onHovered: function(on) { if (on) { root.cursorActive = true; root.cursorIndex = root.lastIndex } }
            onClicked: nm.setAutostart(!nm.autostart)
          }
        }
      }
    }
  }

  component Caption: Text {
    textFormat: Text.PlainText
    width: parent ? parent.width : 0
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  component Stat: Column {
    property string label: ""
    property string value: ""
    spacing: Style.space(2)

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: parent.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: parent.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      elide: Text.ElideRight
    }
  }

  component AdapterRow: CursorSurface {
    id: row
    property var adapter: ({})
    property int rowIndex: 0
    readonly property bool live: adapter.live === true
    readonly property real share: live && nm.totals.down > 0 ? Math.min(1, adapter.down / nm.totals.down) : 0
    readonly property string meta: {
      if (live) {
        var parts = [
          strings.t("adapter.rates").arg(Commons.I18n.formatNumber(adapter.down, 1)).arg(Commons.I18n.formatNumber(adapter.up, 1)),
          strings.tn("adapter.active", adapter.active).arg(Commons.I18n.formatNumber(adapter.active))
        ]
        if (adapter.v4 !== "up" && adapter.v4 !== "") parts.push(strings.t("adapter.v4").arg(adapter.v4))
        if (adapter.v6 !== "up" && adapter.v6 !== "") parts.push(strings.t("adapter.v6").arg(adapter.v6))
        return parts.join(" · ")
      }
      if (!adapter.used) return strings.t("adapter.skipped")
      return adapter.addr4 !== "" ? adapter.addr4 : adapter.addr6
    }

    function focusCap() { cap.field.forceActiveFocus(); cap.field.contentItem.selectAll() }

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex + 1
    foreground: root.foreground
    implicitHeight: content.implicitHeight + Style.spacing.rowPaddingX

    HoverHandler {
      onHoveredChanged: if (hovered) { root.cursorActive = true; root.cursorIndex = row.rowIndex + 1 }
    }

    RowLayout {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        text: Model.adapterGlyph(row.adapter.name)
        color: root.foreground
        opacity: row.adapter.used === false ? 0.5 : 1
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(3)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)
          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: row.adapter.name
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            textFormat: Text.PlainText
            visible: row.adapter.failed > 0
            text: strings.tn("adapter.failed", row.adapter.failed).arg(Commons.I18n.formatNumber(row.adapter.failed))
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: row.meta
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        // Share of the combined download this adapter is carrying.
        Item {
          visible: row.live
          Layout.fillWidth: true
          implicitHeight: Math.max(2, Style.space(3))
          Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.foreground
            opacity: 0.12
          }
          Rectangle {
            width: parent.width * row.share
            height: parent.height
            radius: height / 2
            color: root.foreground
            Behavior on width { NumberAnimation { duration: Style.duration(240); easing.type: Easing.OutCubic } }
          }
        }
      }

      Column {
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.space(2)
        visible: row.adapter.used !== false

        NumberField {
          id: cap
          from: 0
          to: 99999
          stepSize: 5
          value: row.adapter.limit || 0
          fieldWidth: Style.space(72)
          fontSize: Style.font.bodySmall
          foreground: root.foreground
          fontFamily: root.fontFamily
          field.textFromValue: function(v) { return v === 0 ? "∞" : String(v) }
          field.valueFromText: function(t) { var n = parseInt(t, 10); return isFinite(n) ? n : 0 }
          onModified: function(v) { capCommit.pending = v; capCommit.restart() }
        }
        Text {
          textFormat: Text.PlainText
          width: cap.width
          horizontalAlignment: Text.AlignHCenter
          text: strings.t("adapter.cap")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    // Wait for the user to stop scrolling/typing before telling net-merge.
    Timer {
      id: capCommit
      property int pending: 0
      interval: 700
      onTriggered: nm.setLimit(row.adapter.name, pending)
    }
  }
}
