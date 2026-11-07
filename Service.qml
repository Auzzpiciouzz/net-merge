import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Talks to net-merge through bin/net-merge-ctl and keeps the parsed state.
// Owned by Panel.qml; nothing here draws.
Item {
  id: root

  property var settings: ({})
  // Poll faster while the panel is open so the speeds feel live.
  property bool fast: false

  readonly property string ctl: Qt.resolvedUrl("bin/net-merge-ctl").toString().replace(/^file:\/\//, "")

  property bool loaded: false
  property bool installed: true
  property bool trayRunning: false
  property string state: "unknown"
  property string headline: ""
  property string mode: ""
  property string uptime: ""
  property string ipv6: ""
  property bool autostart: false
  property var listed: []
  property var limits: ({})
  property var status: ({ adapters: [] })
  property string lastError: ""

  // Optimistic on/off so the switch throws the moment it is clicked.
  // -1 follows the real state; 0/1 while a change is catching up.
  property int _desired: -1
  readonly property bool on: _desired === -1 ? state === "on" : _desired === 1
  readonly property bool busy: controlProcess.running

  readonly property var adapters: Model.adapterRows(status, listed, limits)
  readonly property var totals: Model.totals(adapters)

  readonly property int refreshIntervalSec: {
    var n = parseInt(String(settings && settings.refreshIntervalSec !== undefined ? settings.refreshIntervalSec : 5), 10)
    return isFinite(n) ? Math.max(2, Math.min(60, n)) : 5
  }

  property bool _wantFull: true

  function refresh(full) {
    if (full) _wantFull = true
    if (pollProcess.running) return
    var withFull = _wantFull
    _wantFull = false
    pollProcess.command = withFull ? ["bash", ctl, "poll", "full"] : ["bash", ctl, "poll"]
    pollProcess.running = true
  }

  function apply(raw, hadFull) {
    var s = Model.sections(raw)
    loaded = true
    installed = !s.missing
    if (!installed) {
      state = "unknown"
      status = { adapters: [] }
      listed = []
      _desired = -1
      return
    }
    trayRunning = s.tray
    var parsed = Model.parseStatus(s.status)
    if (parsed.ok) {
      state = parsed.state
      headline = parsed.headline
      mode = parsed.mode
      uptime = parsed.uptime
      ipv6 = parsed.ipv6
      status = parsed
    }
    limits = Model.parseLimits(s.limits)
    if (hadFull) {
      listed = Model.parseList(s.list)
      autostart = Model.parseAutostart(s.autostart)
    }
    if (_desired !== -1 && (state === "on") === (_desired === 1)) _desired = -1
  }

  function run(args, desired) {
    if (controlProcess.running) return
    lastError = ""
    if (desired !== undefined) _desired = desired
    controlProcess.command = ["bash", ctl].concat(args)
    controlProcess.running = true
  }

  function turnOn() { run(["on"], 1) }
  function turnOff() { run(["off"], 0) }
  function toggle() { if (on) turnOff(); else turnOn() }

  function setLimit(name, mbit) {
    if (!Model.validName(name)) return
    var n = Math.max(0, Math.min(99999, Math.round(Number(mbit) || 0)))
    var next = {}
    for (var k in limits) next[k] = limits[k]
    if (n > 0) next[name] = n
    else delete next[name]
    limits = next
    run(["limit", name, String(n)])
  }

  function setAutostart(value) {
    autostart = value
    run(["autostart", value ? "on" : "off"])
  }

  function elide(text) {
    var v = String(text || "").replace(/\s+/g, " ").trim()
    return v.length > 160 ? v.substring(0, 159) + "…" : v
  }

  onFastChanged: if (fast) refresh(true)

  Timer {
    interval: root.fast ? 2000 : root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  // net-merge takes a moment to bring its adapter up or down; re-poll a few
  // times after a change instead of waiting for the next tick.
  Timer {
    id: settle
    property int ticks: 0
    interval: 800
    repeat: true
    onTriggered: {
      ticks += 1
      root.refresh(true)
      if (ticks >= 5) { ticks = 0; running = false; root._desired = -1 }
    }
  }

  Process {
    id: pollProcess
    property bool full: false
    command: []
    onCommandChanged: full = command.indexOf("full") !== -1
    stdout: StdioCollector { id: pollOut; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) root.apply(String(pollOut.text || ""), pollProcess.full)
    }
  }

  Process {
    id: controlProcess
    command: []
    stdout: StdioCollector { id: controlOut; waitForEnd: true }
    stderr: StdioCollector { id: controlErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) {
        root._desired = -1
        // A key the panel translates, or net-merge's own (English) message.
        var msg = root.elide(controlErr.text || controlOut.text || "")
        root.lastError = code === 124 ? "@timeout" : (msg || "@failed")
      }
      settle.ticks = 0
      settle.restart()
      root.refresh(true)
    }
  }
}
