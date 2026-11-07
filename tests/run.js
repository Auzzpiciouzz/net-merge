// node tests/run.js — exercises Model.js against real net-merge 0.3.6 output.
const fs = require("fs"), path = require("path"), assert = require("assert")
const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma library\s*/, "")
const M = new Function(src + "\nreturn { sections, parseStatus, parseList, parseLimits, parseAutostart, adapterRows, totals, adapterGlyph, formatRate, validName }")()

let passed = 0
function test(name, fn) { try { fn(); passed++ } catch (e) { console.error("FAIL " + name + "\n  " + e.message); process.exitCode = 1 } }

const ON = `net-merge is ON (system-wide (tray), pid 342697, up 8m49s)
IPv6: auto: balanced (every adapter has IPv6)
eno1           v4 up          v6 up          link down   12.5 up   0.2 Mbit/s  via net-merge    0.2  active   2  total     5  w 1.00/1.00  failed 0
wlp0s20f3      v4 up          v6 no route    link down    7.5 up   0.0 Mbit/s  via net-merge    0.1  active   1  total     6  w 0.50/1.00  failed 3`
const LIST = `USE   eno1  v4 192.168.1.39  v6 2001:4490::e45d  (index 2)
USE   wlp0s20f3  v4 192.168.1.40  v6 2001:4490::88df  (index 3)
SKIP  enp0s1  v4 10.0.0.2  (index 4)`

test("on status", () => {
  const s = M.parseStatus(ON)
  assert.equal(s.state, "on"); assert.equal(s.pid, 342697); assert.equal(s.uptime, "8m49s")
  assert.equal(s.mode, "system-wide (tray)"); assert.equal(s.ipv6, "auto: balanced (every adapter has IPv6)")
  assert.equal(s.adapters.length, 2)
  const [a, b] = s.adapters
  assert.deepEqual([a.name, a.v4, a.v6, a.down, a.up, a.via, a.active, a.total, a.failed], ["eno1", "up", "up", 12.5, 0.2, 0.2, 2, 5, 0])
  assert.equal(b.v6, "no route"); assert.equal(b.weightV4, 0.5); assert.equal(b.failed, 3)
})
test("off status", () => {
  const s = M.parseStatus("net-merge is OFF.")
  assert.equal(s.state, "off"); assert.equal(s.adapters.length, 0); assert.equal(s.headline, "net-merge is OFF")
})
test("garbage status", () => { assert.equal(M.parseStatus("segfault\n").ok, false) })
test("list", () => {
  const l = M.parseList(LIST)
  assert.equal(l.length, 3); assert.equal(l[2].used, false); assert.equal(l[0].addr4, "192.168.1.39")
})
test("limits", () => {
  assert.deepEqual(M.parseLimits("eno1           50 Mbit/s\nwlan0 7.6 Mbit/s"), { eno1: 50, wlan0: 8 })
  assert.deepEqual(M.parseLimits("No speed limits set."), {})
})
test("autostart", () => { assert.equal(M.parseAutostart("autostart is ON."), true); assert.equal(M.parseAutostart("autostart is OFF."), false) })
test("sections", () => {
  const s = M.sections("@@tray 1\n@@status\nnet-merge is OFF.\n@@limits\nNo speed limits set.\n@@list\n" + LIST + "\n@@autostart\nautostart is OFF.")
  assert.equal(s.tray, true); assert.equal(s.status, "net-merge is OFF."); assert.equal(M.parseList(s.list).length, 3)
  assert.equal(M.sections("@@missing").missing, true)
})
test("rows merge stats, list and limits", () => {
  const rows = M.adapterRows(M.parseStatus(ON), M.parseList(LIST), { eno1: 50 })
  assert.equal(rows.length, 3); assert.equal(rows[0].limit, 50); assert.equal(rows[0].addr4, "192.168.1.39")
  assert.equal(rows[2].live, false); assert.equal(rows[2].used, false)
  const t = M.totals(rows); assert.equal(t.down, 20); assert.equal(t.live, 2); assert.equal(t.failed, 3)
})
test("markup and hostile names are dropped", () => {
  const evil = `net-merge is ON (x, pid 1, up 1s)
<img src="https://example.invalid/t">  v4 up v6 up link down 1 up 1 Mbit/s
eno1;rm  v4 up v6 up link down 1 up 1 Mbit/s`
  assert.equal(M.parseStatus(evil).adapters.length, 0)
  assert.equal(M.parseList('USE <b>x</b> v4 1.2.3.4').length, 0)
  assert.deepEqual(M.parseLimits('<img/src=x> 5 Mbit/s'), {})
  assert.equal(M.validName("$(reboot)"), false)
})
test("bounds", () => {
  const many = "net-merge is ON (x)\n" + Array.from({ length: 100 }, (_, i) => `eth${i} v4 up v6 up link down 1e99 up -5 Mbit/s`).join("\n")
  const s = M.parseStatus(many); assert.equal(s.adapters.length, 16); assert.equal(s.adapters[0].down, 1e6); assert.equal(s.adapters[0].up, 0)
  assert.ok(M.parseStatus("net-merge is ON (" + "a".repeat(5000) + ")").headline.length <= 120)
})
test("glyph + rate", () => {
  assert.equal(M.adapterGlyph("wlp0s20f3"), "󰖩"); assert.equal(M.adapterGlyph("eno1"), "󰈀"); assert.equal(M.adapterGlyph("enx001122"), "󰄜")
  assert.equal(M.formatRate(12.34), "12.3 Mbit/s"); assert.equal(M.formatRate(1500), "1.50 Gbit/s"); assert.equal(M.formatRate(250), "250 Mbit/s")
})
console.log(passed + " passed" + (process.exitCode ? ", some FAILED" : ""))
