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

// Palette role for the lane glyph, the arrows and the status line. The
// cell itself always wears its level colour (see levelBlend); this is what
// the things *around* it key off. "level" follows the ramp, a parked cell
// goes muted, no battery goes nowhere.
function flowRole(mode) {
  if (mode === "in" || mode === "out" || mode === "full") return "level"
  if (mode === "hold") return "muted"
  return "none"
}

// ---------------------------------------------------------------- level ----
// The cell's colour is its charge: blue when full, sliding to yellow around
// the middle and to red by the low threshold. Three stops, read from the
// theme's colors.toml (blue / yellow / red) unless shell.json overrides them.

function clamp01(value) {
  var v = Number(value)
  if (!isFinite(v)) return 0
  return Math.max(0, Math.min(1, v))
}

// colors.toml → { key: "#rrggbb" } for every six-digit hex value in the file.
// Same line grammar Color.qml uses, so a theme that satisfies the shell
// satisfies this.
function parseThemeColors(raw) {
  var out = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (m) out[m[1].toLowerCase()] = m[2].toLowerCase()
  }
  return out
}

// What a colour token in shell.json means:
//   "#rrggbb" / "#rgb"          literal            → { kind: "hex",  value }
//   "blue", "yellow", "red", …  a colors.toml key  → { kind: "hex",  value }
//   accent | urgent | foreground | muted            → { kind: "role", value }
//   anything else                                   → { kind: "none" }
// Roles are resolved by the caller, which owns the live palette.
function resolveColorToken(token, theme) {
  var t = String(token || "").trim().toLowerCase()
  if (/^#[0-9a-f]{6}$/.test(t)) return { kind: "hex", value: t }
  if (/^#[0-9a-f]{3}$/.test(t)) {
    return { kind: "hex", value: "#" + t.charAt(1) + t.charAt(1) + t.charAt(2) + t.charAt(2) + t.charAt(3) + t.charAt(3) }
  }
  var th = theme || {}
  if (t && typeof th[t] === "string") return { kind: "hex", value: th[t] }
  if (t === "accent" || t === "urgent" || t === "foreground" || t === "muted") return { kind: "role", value: t }
  return { kind: "none" }
}

// Where the cell sits on the ramp, as a blend of two stops:
//   { from: "full" | "mid" | "low", to: same, t: 0..1 }
// Blue holds from 100% down to `top`, slides to yellow by `mid`, then to red
// by the low threshold, below which it stays red. The knees float with the
// threshold so a high threshold still gets a yellow band above it.
function levelBlend(fraction, lowFraction) {
  var f = clamp01(fraction)
  var low = Number(lowFraction)
  if (!isFinite(low)) low = 0.2
  low = Math.min(0.6, clamp01(low))
  var mid = Math.max(low + 0.15, 0.5)
  var top = Math.max(mid + 0.15, 0.85)
  if (f >= top) return { from: "full", to: "full", t: 0 }
  if (f > mid) return { from: "full", to: "mid", t: (top - f) / (top - mid) }
  if (f > low) return { from: "mid", to: "low", t: (mid - f) / (mid - low) }
  return { from: "low", to: "low", t: 0 }
}

// RGB ↔ HSV, components 0..1, hue 0..1 (-1 when there is none).
function rgbToHsv(c) {
  var r = clamp01(c && c.r), g = clamp01(c && c.g), b = clamp01(c && c.b)
  var max = Math.max(r, g, b), min = Math.min(r, g, b)
  var d = max - min
  var h = -1
  if (d > 0) {
    if (max === r) h = ((g - b) / d) % 6
    else if (max === g) h = (b - r) / d + 2
    else h = (r - g) / d + 4
    h /= 6
    if (h < 0) h += 1
  }
  return { h: h, s: max > 0 ? d / max : 0, v: max }
}

function hsvToRgb(h, s, v) {
  var hh = ((Number(h) || 0) % 1 + 1) % 1 * 6
  var ss = clamp01(s), vv = clamp01(v)
  var i = Math.floor(hh)
  var f = hh - i
  var p = vv * (1 - ss), q = vv * (1 - ss * f), t = vv * (1 - ss * (1 - f))
  var r, g, b
  switch (i % 6) {
    case 0: r = vv; g = t; b = p; break
    case 1: r = q; g = vv; b = p; break
    case 2: r = p; g = vv; b = t; break
    case 3: r = p; g = q; b = vv; break
    case 4: r = t; g = p; b = vv; break
    default: r = vv; g = p; b = q
  }
  return { r: r, g: g, b: b }
}

// The blend walks the hue wheel *downward* (blue → cyan → green → yellow →
// orange → red), which is the way a battery ramp reads. A straight RGB lerp
// from blue to yellow cuts through grey; the short way round the wheel goes
// through magenta. Only when the downward walk would be more than three
// quarters of a turn does it go the other way. Inputs are {r,g,b} in 0..1 — a
// QML colour object qualifies — and so is the result.
function mixRgb(a, b, t) {
  var t1 = clamp01(t)
  if (t1 <= 0) return { r: clamp01(a && a.r), g: clamp01(a && a.g), b: clamp01(a && a.b) }
  if (t1 >= 1) return { r: clamp01(b && b.r), g: clamp01(b && b.g), b: clamp01(b && b.b) }
  var A = rgbToHsv(a), B = rgbToHsv(b)
  var ha = A.h < 0 ? B.h : A.h
  var hb = B.h < 0 ? A.h : B.h
  var h
  if (ha < 0 && hb < 0) h = 0
  else {
    var down = ha - hb
    if (down < 0) down += 1
    var d = down <= 0.75 ? -down : (1 - down)
    h = ha + d * t1
    if (h < 0) h += 1
    if (h >= 1) h -= 1
  }
  return hsvToRgb(h, A.s + (B.s - A.s) * t1, A.v + (B.v - A.v) * t1)
}

// ---------------------------------------------------------------- glow ----
// A theme's blue is not always a glow. 2-haxorz hands over #2b5e8f on a
// #0b1b2b bar — 2.6:1, the same navy as its accent — and a cell wearing it
// faithfully vanishes into the bar, reading exactly like the stock glyph.
// glowReady is the guarantee that a stop can be seen. A stop that stands out
// from the bar (WCAG contrast of `minRatio`) and is a colour rather than a
// tinted grey comes back untouched — nord's, gruvbox's and everforest's
// pastels sit at 0.28–0.33 saturation and are glows. One that fails either
// test keeps its hue, has its saturation lifted to `minS` and its value
// walked away from the bar until the ratio is met: brighter on a dark bar,
// darker on a light one. 2-haxorz's yellow and red are the tinted-grey
// case, 0.23 with fine contrast, and a halo in them is a smudge. A grey or
// near-grey stop stays grey, so a monochrome theme keeps its restraint. A
// pure hue that cannot reach the ratio at full brightness leans towards
// white rather than giving up.

function hexToRgb(hex) {
  var m = String(hex || "").trim().match(/^#([0-9a-f]{2})?([0-9a-f]{6})$/i)
  if (!m) return null
  var n = parseInt(m[2], 16)
  return { r: ((n >> 16) & 255) / 255, g: ((n >> 8) & 255) / 255, b: (n & 255) / 255 }
}

function rgbToHex(c) {
  function pair(x) {
    var s = Math.round(clamp01(x) * 255).toString(16)
    return s.length < 2 ? "0" + s : s
  }
  return "#" + pair(c && c.r) + pair(c && c.g) + pair(c && c.b)
}

// WCAG relative luminance of {r,g,b} in 0..1.
function luminance(c) {
  function lin(x) {
    var v = clamp01(x)
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
  }
  return 0.2126 * lin(c && c.r) + 0.7152 * lin(c && c.g) + 0.0722 * lin(c && c.b)
}

// WCAG contrast ratio between two {r,g,b} colours, 1..21.
function contrastRatio(a, b) {
  var la = luminance(a), lb = luminance(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

var GLOW_MIN_S = 0.55      // a rescued stop is lifted to at least this
var GLOW_MUDDY_S = 0.25    // under this a coloured stop is a tinted grey, not a colour
var GLOW_GREY_S = 0.15     // at or under this a stop is grey and stays grey
var GLOW_MIN_RATIO = 4.5   // WCAG AA text; the themes that glow sit at 5.5–7.5
var GLOW_MID_LUMA = 0.179  // where black and white contrast equally; above = light bar

function glowReady(hex, bgHex, minS, minRatio) {
  var c = hexToRgb(hex)
  if (!c) return String(hex || "")
  var bg = hexToRgb(bgHex) || { r: 0, g: 0, b: 0 }
  var sFloor = Number(minS)
  if (!isFinite(sFloor)) sFloor = GLOW_MIN_S
  sFloor = clamp01(sFloor)
  var ratio = Number(minRatio)
  if (!isFinite(ratio) || ratio < 1) ratio = GLOW_MIN_RATIO

  var hsv = rgbToHsv(c)
  var grey = hsv.h < 0 || hsv.s <= GLOW_GREY_S
  var muddy = !grey && hsv.s < GLOW_MUDDY_S
  if (!muddy && contrastRatio(c, bg) >= ratio) return rgbToHex(c)

  var h = hsv.h < 0 ? 0 : hsv.h
  var s = grey ? hsv.s : Math.max(hsv.s, sFloor)
  var v = hsv.v
  var lightBar = luminance(bg) > GLOW_MID_LUMA
  var out = hsvToRgb(h, s, v)
  for (var i = 0; i < 120 && contrastRatio(out, bg) < ratio; i++) {
    if (lightBar) {
      if (v <= 0) break
      v = Math.max(0, v - 0.02)
    } else if (v < 1) {
      v = Math.min(1, v + 0.02)
    } else if (s > 0) {
      s = Math.max(0, s - 0.02)
    } else break
    out = hsvToRgb(h, s, v)
  }
  return rgbToHex(out)
}

// A look at the cell in any state, without touching the battery:
// `omarchy-shell omarchy.power preview out 35`. Null clears it.
function previewState(mode, percent) {
  var m = String(mode || "").trim().toLowerCase()
  if (m === "" || m === "off" || m === "live") return null
  if (["in", "out", "hold", "full"].indexOf(m) < 0) return null
  var p = Number(percent)
  if (!isFinite(p)) p = 50
  p = Math.max(0, Math.min(100, Math.round(p)))
  if (m === "full") p = 100
  return { mode: m, fraction: p / 100, watts: m === "in" ? 45 : (m === "out" ? 18 : 0) }
}

// A deterministic 0..1 per (index, salt): the classic sin-hash. Not random —
// the same index always gets the same number, so a spark's personality never
// changes under you between binding evaluations.
function hash01(n, salt) {
  var x = Math.sin((Number(n) || 0) * 12.9898 + (Number(salt) || 0) * 78.233) * 43758.5453
  return x - Math.floor(x)
}

// One atom's personality in the stream: size and brightness, the band it
// rides (fractions of the cell height: the low end and the high end), when it
// sets off and how long it rests, both as multiples of the base period. A
// stream with every atom on the same line and the same clock is a convoy.
function sparkSpec(index, count) {
  var i = Math.max(0, Math.floor(Number(index) || 0))
  var n = Math.max(1, Math.floor(Number(count) || 1))
  var k = i + 1
  return {
    size: 0.7 + 0.6 * hash01(k, 1),
    yFrom: 0.55 + 0.3 * hash01(k, 2),
    yTo: 0.15 + 0.3 * hash01(k, 3),
    delay: i / n + 0.25 * hash01(k, 4),
    speed: 0.8 + 0.45 * hash01(k, 5),
    peak: 0.7 + 0.3 * hash01(k, 6),
    rest: 0.1 + 0.5 * hash01(k, 7)
  }
}

// One glint's personality: where it pops (fractions of the flow region), how
// big, when, how long it waits before popping again, and which way it spins.
function twinkleSpec(index, count) {
  var i = Math.max(0, Math.floor(Number(index) || 0))
  var n = Math.max(1, Math.floor(Number(count) || 1))
  var k = i + 1
  return {
    x: hash01(k, 8),
    y: hash01(k, 9),
    size: 0.6 + 0.8 * hash01(k, 10),
    delay: (i / n) * 1.6 + 0.8 * hash01(k, 11),
    rest: 0.6 + 1.6 * hash01(k, 12),
    spin: hash01(k, 13) > 0.5 ? 90 : -90
  }
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
    clamp01: clamp01,
    parseThemeColors: parseThemeColors,
    resolveColorToken: resolveColorToken,
    levelBlend: levelBlend,
    rgbToHsv: rgbToHsv,
    hsvToRgb: hsvToRgb,
    mixRgb: mixRgb,
    hexToRgb: hexToRgb,
    rgbToHex: rgbToHex,
    luminance: luminance,
    contrastRatio: contrastRatio,
    glowReady: glowReady,
    previewState: previewState,
    hash01: hash01,
    sparkSpec: sparkSpec,
    twinkleSpec: twinkleSpec,
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
