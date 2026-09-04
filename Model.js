// Pure functions only. Loaded by Panel.qml / FluxCell.qml as a QML library and
// by test/model.test.js under node — no QML, no Quickshell, no DOM in here.

// ---------------------------------------------------------------- stock ----
// Everything down to modeLabel() is the stock omarchy.power model, unchanged,
// so the keyboard picker, threshold logic and icon ladder behave exactly as
// they did before the overhaul.

function clampIndex(index, length) {
  if (length <= 0) return 0
  return Math.max(0, Math.min(length - 1, index))
}

function selectProfileIndex(index, delta, profiles) {
  var values = Array.isArray(profiles) ? profiles : []
  if (values.length === 0) return 0
  return clampIndex(index + delta, values.length)
}

function parseKeyValue(raw) {
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf("\t")
    if (idx <= 0) continue
    next[lines[i].substring(0, idx)] = lines[i].substring(idx + 1).trim()
  }
  return next
}

function parseProfiles(raw, previousIndex) {
  var lines = String(raw || "").split("\n")
  var list = []
  var active = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    list.push(parts[0])
    if (parts[1] === "1") active = parts[0]
  }
  return {
    profiles: list,
    activeProfile: active,
    profileIndex: clampIndex(previousIndex || 0, list.length)
  }
}

function profileIcon(name) {
  if (name === "power-saver") return "󰌪"
  if (name === "balanced") return "󰊚"
  if (name === "performance") return "󰓅"
  return "󰂄"
}

function batteryFraction(device) {
  return device && device.isPresent ? Math.max(0, Math.min(1, device.percentage)) : 0
}

function chargeThresholdActive(device, onBattery, states) {
  var d = device || {}
  var s = states || {}
  if (!(d && d.isPresent && !onBattery)) return false

  var fraction = batteryFraction(d)
  if (d.state === s.Discharging) return false
  if (d.state === s.PendingCharge) return true
  if (d.state === s.FullyCharged && fraction < 0.99) return true
  if (d.state !== s.Charging || fraction >= 0.99) return false

  return Number(d.changeRate || 0) <= 0.2 || Number(d.timeToFull || 0) >= 8 * 60 * 60
}

function batteryIcon(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  var index = Math.max(0, Math.min(9, Math.floor(d.percentage * 10)))
  var threshold = chargeThresholdActive(d, onBattery, states)

  if (threshold) return defaultIcons[index]
  if (d.state === states.FullyCharged) return "󰂅"
  if (!onBattery) return chargingIcons[index]
  return defaultIcons[index]
}

function modeLabel(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var percentage = d.isPresent ? d.percentage : 0
  if (chargeThresholdActive(d, onBattery, states)) return "Threshold"
  if (onBattery) return "On battery"
  if (!onBattery && percentage >= 1) return "Fully charged"
  return "Charging"
}

// ----------------------------------------------------------------- flux ----

// What the power is doing, as one word the whole widget keys off:
//   none — no battery
//   in   — on AC and the cell is filling
//   out  — on battery, the cell is draining
//   hold — on AC but a charge threshold is keeping it parked
//   full — on AC, fully charged, nothing moving
function flowMode(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return "none"
  if (chargeThresholdActive(d, onBattery, states)) return "hold"
  if (onBattery) return "out"
  var s = states || {}
  if (d.state === s.FullyCharged || batteryFraction(d) >= 1) return "full"
  return "in"
}

// Low only matters while draining: a 5% battery on the charger is fine.
function isLow(fraction, mode, threshold) {
  var t = Number(threshold)
  if (!isFinite(t)) t = 20
  return mode === "out" && Math.round(Math.max(0, Math.min(1, Number(fraction) || 0)) * 100) <= t
}

// Palette role for the glow, the fill and the sparks.
function flowRole(mode, low) {
  if (mode === "out") return low ? "urgent" : "foreground"
  if (mode === "in" || mode === "full") return "accent"
  if (mode === "hold") return "muted"
  return "none"
}

// Signed watts for the trace: up is in, down is out, flat is parked.
function signedWatts(mode, watts) {
  var w = Math.abs(Number(watts) || 0)
  if (mode === "in") return w
  if (mode === "out") return -w
  return 0
}

// Spark travel time. More watts, faster sparks; 60 W and up runs at the floor
// (40% of base) so a heavy draw reads as a rush without becoming a blur.
function pipPeriod(watts, base) {
  var w = Math.max(0, Math.min(60, Number(watts) || 0))
  var b = Number(base)
  if (!isFinite(b) || b <= 0) b = 1500
  return Math.round(b * (1 - 0.6 * (w / 60)))
}

function formatWatts(watts, digits) {
  var w = Number(watts)
  if (!isFinite(w)) return "—"
  var n = digits === undefined ? 1 : digits
  var s = Math.abs(w).toFixed(n).replace(/\.0+$/, "")
  return s + " W"
}

function formatDuration(seconds) {
  var s = Number(seconds)
  if (!isFinite(s) || s <= 0) return "—"
  var h = Math.floor(s / 3600)
  var m = Math.round((s - h * 3600) / 60)
  if (m === 60) { h += 1; m = 0 }
  if (h <= 0) return m + "m"
  return m > 0 ? h + "h " + m + "m" : h + "h"
}

function formatVolts(volts) {
  var v = Number(volts)
  if (!isFinite(v) || v <= 0) return "—"
  return v.toFixed(1) + " V"
}

function formatWattHours(wh) {
  var v = Number(wh)
  if (!isFinite(v) || v <= 0) return "—"
  return v.toFixed(1).replace(/\.0$/, "") + " Wh"
}

// Percent of design capacity the cell can still hold. -1 when unknown.
function healthPercent(full, design) {
  var f = Number(full)
  var d = Number(design)
  if (!isFinite(f) || !isFinite(d) || d <= 0 || f <= 0) return -1
  return Math.max(0, Math.min(100, Math.round(f / d * 100)))
}

// Quickshell reports healthPercentage on some builds as 0..100 and on others
// as 0..1; a battery at 1% health is not a thing, so <= 1 means a fraction.
function normalizePercent(value) {
  var v = Number(value)
  if (!isFinite(v) || v < 0) return -1
  return Math.round(v <= 1 ? v * 100 : v)
}

// The sysfs probe: "name<TAB>value" lines from /sys/class/power_supply/BATn.
// Kernel units are micro-everything. power_now is preferred because it is the
// instantaneous reading; current_now * voltage_now is the fallback on cells
// that expose charge instead of energy.
function parseSysfs(raw) {
  var kv = parseKeyValue(raw)
  var out = {}
  var pn = Number(kv.power_now)
  var cn = Number(kv.current_now)
  var vn = Number(kv.voltage_now)
  if (kv.power_now !== undefined && isFinite(pn)) out.watts = Math.abs(pn) / 1e6
  else if (kv.current_now !== undefined && kv.voltage_now !== undefined && isFinite(cn) && isFinite(vn)) out.watts = Math.abs(cn * vn) / 1e12
  if (kv.voltage_now !== undefined && isFinite(vn)) out.volts = vn / 1e6
  if (kv.status !== undefined) out.status = String(kv.status).toLowerCase()
  var ef = Number(kv.energy_full)
  var efd = Number(kv.energy_full_design)
  var cf = Number(kv.charge_full)
  var cfd = Number(kv.charge_full_design)
  if (kv.energy_full !== undefined && isFinite(ef)) out.full = ef / 1e6
  else if (kv.charge_full !== undefined && isFinite(cf)) out.full = cf / 1e6
  if (kv.energy_full_design !== undefined && isFinite(efd)) out.fullDesign = efd / 1e6
  else if (kv.charge_full_design !== undefined && isFinite(cfd)) out.fullDesign = cfd / 1e6
  return out
}

// Ring buffer as a fresh array: reassigning the QML property is what makes
// the trace repaint, mutating in place would not.
function pushSample(history, value, capacity) {
  var list = Array.isArray(history) ? history.slice() : []
  list.push(Number(value) || 0)
  var cap = Math.max(1, Math.floor(Number(capacity)) || 1)
  while (list.length > cap) list.shift()
  return list
}

function peakWatts(samples) {
  var peak = 0
  var list = Array.isArray(samples) ? samples : []
  for (var i = 0; i < list.length; i++) peak = Math.max(peak, Math.abs(Number(list[i]) || 0))
  return peak
}

// What the top (and bottom) edge of the trace means: the smallest "nice"
// step that still contains the peak, never below the floor so a quiet hour
// does not blow a 2 W idle up into a mountain range.
function traceScale(samples, floor) {
  var steps = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 360, 480]
  var f = Number(floor)
  if (!isFinite(f) || f <= 0) f = 10
  var need = Math.max(peakWatts(samples), f)
  for (var i = 0; i < steps.length; i++) if (steps[i] >= need) return steps[i]
  return Math.ceil(need / 60) * 60
}

function statusLine(mode, watts, thresholdText) {
  if (mode === "in") return "Charging · " + formatWatts(watts) + " in"
  if (mode === "out") return "On battery · " + formatWatts(watts) + " out"
  if (mode === "hold") return "Holding" + (thresholdText ? " at " + thresholdText : "")
  if (mode === "full") return "Fully charged · on AC"
  return ""
}

function tooltip(mode, percent, watts, timeText, thresholdText) {
  var p = Math.round(Number(percent) || 0)
  var hasTime = typeof timeText === "string" && timeText !== "" && timeText !== "—"
  var parts = []
  if (mode === "in") {
    parts.push("Charging " + p + "%")
    parts.push(formatWatts(watts) + " in")
    if (hasTime) parts.push(timeText + " to full")
  } else if (mode === "out") {
    parts.push("On battery " + p + "%")
    parts.push(formatWatts(watts) + " out")
    if (hasTime) parts.push(timeText + " left")
  } else if (mode === "hold") {
    parts.push("Holding at " + (thresholdText || (p + "%")))
  } else if (mode === "full") {
    parts.push("Fully charged")
    parts.push("on AC")
  }
  return parts.join("  ·  ")
}

// Which Glyphs.js key sits at the far end of the wire.
function laneKey(mode) {
  if (mode === "out") return "laptop"
  if (mode === "none") return ""
  return "plug"
}

function trendKey(mode) {
  if (mode === "in") return "arrowUp"
  if (mode === "out") return "arrowDown"
  return ""
}

function nextProfile(profiles, active) {
  var list = Array.isArray(profiles) ? profiles : []
  if (list.length === 0) return ""
  var i = list.indexOf(active)
  return list[(i + 1) % list.length]
}

// UPower hands out "BAT0"; some builds hand out the full sysfs path.
function sysfsPath(nativePath) {
  var p = String(nativePath || "").trim()
  if (!p) p = "BAT0"
  return p.charAt(0) === "/" ? p : "/sys/class/power_supply/" + p
}

function upowerSeconds(device, mode) {
  var d = device || {}
  if (mode === "in") return Number(d.timeToFull) || 0
  if (mode === "out") return Number(d.timeToEmpty) || 0
  return 0
}

if (typeof module !== "undefined") {
  module.exports = {
    clampIndex: clampIndex,
    selectProfileIndex: selectProfileIndex,
    parseKeyValue: parseKeyValue,
    parseProfiles: parseProfiles,
    profileIcon: profileIcon,
    batteryFraction: batteryFraction,
    chargeThresholdActive: chargeThresholdActive,
    batteryIcon: batteryIcon,
    modeLabel: modeLabel,
    flowMode: flowMode,
    isLow: isLow,
    flowRole: flowRole,
    signedWatts: signedWatts,
    pipPeriod: pipPeriod,
    formatWatts: formatWatts,
    formatDuration: formatDuration,
    formatVolts: formatVolts,
    formatWattHours: formatWattHours,
    healthPercent: healthPercent,
    normalizePercent: normalizePercent,
    parseSysfs: parseSysfs,
    pushSample: pushSample,
    peakWatts: peakWatts,
    traceScale: traceScale,
    statusLine: statusLine,
    tooltip: tooltip,
    laneKey: laneKey,
    trendKey: trendKey,
    nextProfile: nextProfile,
    sysfsPath: sysfsPath,
    upowerSeconds: upowerSeconds
  }
}
