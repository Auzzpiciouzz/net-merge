.pragma library

// Pure parsing for net-merge's CLI output. No QML imports, so tests/run.js can
// load it under node. Everything here treats its input as untrusted: lengths are
// capped, numbers are clamped, and only fixed key words are interpreted.

var MAX_ADAPTERS = 16
var MAX_LINE = 400
var NAME_RE = /^[A-Za-z0-9._:@-]{1,32}$/

// Keys that start a new field on a `net-merge status` adapter line.
var KEYS = { v4: 1, v6: 1, link: 1, down: 1, up: 1, "Mbit/s": 1, via: 1, active: 1, total: 1, w: 1, failed: 1 }

function num(value) {
  var n = parseFloat(value)
  if (!isFinite(n) || n < 0) return 0
  return Math.min(n, 1e6)
}

function int(value) {
  var n = parseInt(value, 10)
  if (!isFinite(n) || n < 0) return 0
  return Math.min(n, 1e9)
}

function clip(text, max) {
  var s = String(text === undefined || text === null ? "" : text)
  return s.length > max ? s.substring(0, max - 1) + "…" : s
}

function validName(name) {
  return NAME_RE.test(String(name || ""))
}

function lines(raw) {
  return String(raw || "").split(/\r?\n/).map(function(l) { return l.length > MAX_LINE ? l.substring(0, MAX_LINE) : l })
}

// Splits the poll helper's output into its @@-headed sections.
function sections(raw) {
  var out = { tray: false, missing: false, status: "", limits: "", list: "", autostart: "" }
  var current = null
  var buf = []
  function flush() {
    if (current && current in out && typeof out[current] === "string") out[current] = buf.join("\n")
    buf = []
  }
  var all = lines(raw)
  for (var i = 0; i < all.length; i++) {
    var line = all[i]
    var m = line.match(/^@@(\w+)(?:\s+(\S+))?$/)
    if (m) {
      flush()
      if (m[1] === "tray") { out.tray = m[2] === "1"; current = null }
      else if (m[1] === "missing") { out.missing = true; current = null }
      else current = m[1]
      continue
    }
    if (current) buf.push(line)
  }
  flush()
  return out
}

// One adapter line of `net-merge status` while ON, e.g.
// eno1  v4 up  v6 up  link down 12.3 up 0.2 Mbit/s  via net-merge 0.2  active 2  total 5  w 1.00/1.00  failed 0
function parseAdapterLine(line) {
  var tokens = String(line || "").trim().split(/\s+/)
  if (tokens.length < 3 || !validName(tokens[0]) || tokens[1] !== "v4") return null
  var a = { name: tokens[0], v4: "", v6: "", down: 0, up: 0, via: 0, active: 0, total: 0, weightV4: 0, weightV6: 0, failed: 0 }
  var i = 1
  while (i < tokens.length) {
    var t = tokens[i]
    if (t === "v4" || t === "v6") {
      // The value always takes the next token (it may itself be "up"), then
      // any further words until the next key.
      var words = []
      i++
      if (i < tokens.length) words.push(tokens[i++])
      while (i < tokens.length && !(tokens[i] in KEYS)) words.push(tokens[i++])
      a[t] = clip(words.join(" "), 24)
    } else if (t === "down" || t === "up") {
      a[t] = num(tokens[i + 1]); i += 2
    } else if (t === "via") {
      // "via net-merge 0.2"
      a.via = num(tokens[i + 2]); i += 3
    } else if (t === "active" || t === "total" || t === "failed") {
      a[t] = int(tokens[i + 1]); i += 2
    } else if (t === "w") {
      var parts = String(tokens[i + 1] || "").split("/")
      a.weightV4 = num(parts[0])
      a.weightV6 = num(parts.length > 1 ? parts[1] : parts[0])
      i += 2
    } else {
      i++
    }
  }
  return a
}

// `net-merge status`. First line is "net-merge is ON (...)." or "net-merge is OFF."
function parseStatus(raw) {
  var all = lines(raw)
  var result = { ok: false, state: "unknown", headline: "", mode: "", pid: 0, uptime: "", ipv6: "", adapters: [] }
  for (var i = 0; i < all.length; i++) {
    var line = all[i]
    var head = line.match(/^net-merge is (\w+)\b\s*(?:\((.*)\))?/)
    if (head) {
      result.ok = true
      result.state = head[1].toLowerCase()
      result.headline = clip(line.trim().replace(/\.$/, ""), 120)
      var detail = head[2] || ""
      var mode = detail.match(/^([^,]+)/)
      var pid = detail.match(/pid (\d+)/)
      var up = detail.match(/up ([0-9hms.]+)/)
      result.mode = mode ? clip(mode[1].trim(), 40) : ""
      result.pid = pid ? int(pid[1]) : 0
      result.uptime = up ? clip(up[1], 16) : ""
      continue
    }
    var v6 = line.match(/^IPv6:\s*(.+)$/)
    if (v6) { result.ipv6 = clip(v6[1].trim(), 120); continue }
    if (result.adapters.length >= MAX_ADAPTERS) continue
    var adapter = parseAdapterLine(line)
    if (adapter) result.adapters.push(adapter)
  }
  return result
}

// `net-merge list`: "USE   eno1  v4 192.168.1.39  v6 2001:…  (index 2)"
function parseList(raw) {
  var out = []
  var all = lines(raw)
  for (var i = 0; i < all.length && out.length < MAX_ADAPTERS; i++) {
    var m = all[i].match(/^\s*([A-Z]+)\s+(\S+)(.*)$/)
    if (!m || !validName(m[2])) continue
    var rest = m[3]
    var v4 = rest.match(/\bv4\s+(\S+)/)
    var v6 = rest.match(/\bv6\s+(\S+)/)
    out.push({
      name: m[2],
      used: m[1] === "USE",
      flag: clip(m[1], 8),
      addr4: v4 ? clip(v4[1], 48) : "",
      addr6: v6 ? clip(v6[1], 48) : ""
    })
  }
  return out
}

// `net-merge limit`: "eno1           50 Mbit/s" per capped adapter, or "No speed limits set."
function parseLimits(raw) {
  var out = {}
  var all = lines(raw)
  for (var i = 0; i < all.length; i++) {
    var m = all[i].match(/^\s*(\S+)\s+([\d.]+)\s*Mbit\/s\s*$/)
    if (m && validName(m[1])) out[m[1]] = Math.round(num(m[2]))
  }
  return out
}

function parseAutostart(raw) {
  var m = String(raw || "").match(/autostart is (ON|OFF)/i)
  return m ? m[1].toUpperCase() === "ON" : false
}

// Merge the ON-state stats, the adapter list, and limits into one row model.
function adapterRows(status, listed, limits) {
  var byName = {}
  var rows = []
  var i
  var statusAdapters = status && status.adapters ? status.adapters : []
  for (i = 0; i < statusAdapters.length; i++) {
    var a = statusAdapters[i]
    var row = {}
    for (var k in a) row[k] = a[k]
    row.used = true
    row.addr4 = ""
    row.addr6 = ""
    row.live = true
    byName[a.name] = row
    rows.push(row)
  }
  for (i = 0; listed && i < listed.length; i++) {
    var l = listed[i]
    var existing = byName[l.name]
    if (existing) {
      existing.addr4 = l.addr4
      existing.addr6 = l.addr6
      continue
    }
    if (rows.length >= MAX_ADAPTERS) break
    var fresh = { name: l.name, used: l.used, flag: l.flag, addr4: l.addr4, addr6: l.addr6, live: false,
                  v4: "", v6: "", down: 0, up: 0, via: 0, active: 0, total: 0, weightV4: 0, weightV6: 0, failed: 0 }
    byName[l.name] = fresh
    rows.push(fresh)
  }
  for (i = 0; i < rows.length; i++) rows[i].limit = limits && limits[rows[i].name] ? limits[rows[i].name] : 0
  return rows
}

function totals(rows) {
  var t = { down: 0, up: 0, active: 0, total: 0, failed: 0, live: 0 }
  for (var i = 0; rows && i < rows.length; i++) {
    if (!rows[i].live) continue
    t.down += rows[i].down
    t.up += rows[i].up
    t.active += rows[i].active
    t.total += rows[i].total
    t.failed += rows[i].failed
    t.live += 1
  }
  return t
}

// Nerd Font glyph for an adapter, from its kernel name.
function adapterGlyph(name) {
  var n = String(name || "")
  if (/^(wl|wlan|wifi|ath|ra)/.test(n)) return "󰖩"
  if (/^(usb|rndis|enx|wwan|wwp)/.test(n)) return "󰄜"
  return "󰈀"
}

function formatRate(mbit, formatNumber) {
  var v = num(mbit)
  var fmt = typeof formatNumber === "function" ? formatNumber : function(x, d) { return x.toFixed(d) }
  if (v >= 1000) return fmt(v / 1000, 2) + " Gbit/s"
  return fmt(v, v >= 100 ? 0 : 1) + " Mbit/s"
}
