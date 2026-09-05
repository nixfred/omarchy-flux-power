const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

const states = { Charging: 1, Discharging: 2, FullyCharged: 4, PendingCharge: 5 }
const device = (over) => Object.assign({ isPresent: true, percentage: 0.92, state: states.Discharging, changeRate: 18.3, timeToFull: 0, timeToEmpty: 3.4 * 3600 }, over)

test("flowMode: the five states", () => {
  assert.equal(Model.flowMode(null, false, states), "none")
  assert.equal(Model.flowMode({ isPresent: false }, false, states), "none")
  assert.equal(Model.flowMode(device(), true, states), "out")
  assert.equal(Model.flowMode(device({ state: states.Charging }), false, states), "in")
  assert.equal(Model.flowMode(device({ state: states.FullyCharged, percentage: 1 }), false, states), "full")
  // Parked below 99% on AC, not discharging → threshold hold.
  assert.equal(Model.flowMode(device({ state: states.PendingCharge, percentage: 0.8 }), false, states), "hold")
  assert.equal(Model.flowMode(device({ state: states.FullyCharged, percentage: 0.8 }), false, states), "hold")
})

test("isLow only bites while draining", () => {
  assert.equal(Model.isLow(0.15, "out", 20), true)
  assert.equal(Model.isLow(0.20, "out", 20), true)
  assert.equal(Model.isLow(0.21, "out", 20), false)
  assert.equal(Model.isLow(0.05, "in", 20), false)
  assert.equal(Model.isLow(0.05, "out", "nonsense"), true, "bad threshold falls back to 20")
})

test("flowRole: moving or full follows the level, parked is muted", () => {
  assert.equal(Model.flowRole("in"), "level")
  assert.equal(Model.flowRole("full"), "level")
  assert.equal(Model.flowRole("out"), "level")
  assert.equal(Model.flowRole("hold"), "muted")
  assert.equal(Model.flowRole("none"), "none")
})

test("parseThemeColors reads every hex key out of colors.toml", () => {
  const toml = 'mode = "dark"\n\naccent = "#7d82d9"\nforeground = "#ffcead"\nred = "#ED5B5A"\nyellow = "#E9BB4F"\nblue = "#7d82d9"\nnot_a_color = "dark"\n'
  const t = Model.parseThemeColors(toml)
  assert.deepEqual(t, { accent: "#7d82d9", foreground: "#ffcead", red: "#ed5b5a", yellow: "#e9bb4f", blue: "#7d82d9" })
  assert.deepEqual(Model.parseThemeColors(""), {})
})

test("resolveColorToken: hex, theme key, role, nothing", () => {
  const theme = { blue: "#7d82d9", yellow: "#e9bb4f" }
  assert.deepEqual(Model.resolveColorToken("#AbCdEf", theme), { kind: "hex", value: "#abcdef" })
  assert.deepEqual(Model.resolveColorToken("#fc0", theme), { kind: "hex", value: "#ffcc00" })
  assert.deepEqual(Model.resolveColorToken("blue", theme), { kind: "hex", value: "#7d82d9" })
  assert.deepEqual(Model.resolveColorToken(" Yellow ", theme), { kind: "hex", value: "#e9bb4f" })
  assert.deepEqual(Model.resolveColorToken("accent", theme), { kind: "role", value: "accent" })
  assert.deepEqual(Model.resolveColorToken("urgent", {}), { kind: "role", value: "urgent" })
  assert.deepEqual(Model.resolveColorToken("red", {}), { kind: "none" }, "a theme without the key is a miss, not a guess")
  assert.deepEqual(Model.resolveColorToken("", theme), { kind: "none" })
  assert.deepEqual(Model.resolveColorToken(undefined, theme), { kind: "none" })
})

test("levelBlend: blue holds to 85%, yellow at 50%, red by the threshold", () => {
  assert.deepEqual(Model.levelBlend(1.0, 0.2), { from: "full", to: "full", t: 0 })
  assert.deepEqual(Model.levelBlend(0.85, 0.2), { from: "full", to: "full", t: 0 })
  const upper = Model.levelBlend(0.675, 0.2)
  assert.equal(upper.from, "full"); assert.equal(upper.to, "mid")
  assert.ok(Math.abs(upper.t - 0.5) < 1e-9)
  const atMid = Model.levelBlend(0.5, 0.2)
  assert.equal(atMid.from, "mid"); assert.equal(atMid.to, "low"); assert.equal(atMid.t, 0)
  const lower = Model.levelBlend(0.35, 0.2)
  assert.equal(lower.from, "mid"); assert.equal(lower.to, "low")
  assert.ok(Math.abs(lower.t - 0.5) < 1e-9)
  assert.deepEqual(Model.levelBlend(0.2, 0.2), { from: "low", to: "low", t: 0 })
  assert.deepEqual(Model.levelBlend(0.0, 0.2), { from: "low", to: "low", t: 0 })
})

test("levelBlend: the knees float with a high threshold and survive junk", () => {
  // threshold 40% → yellow at 55%, blue from 85%
  assert.deepEqual(Model.levelBlend(0.55, 0.4), { from: "mid", to: "low", t: 0 })
  assert.equal(Model.levelBlend(0.7, 0.4).to, "mid")
  assert.deepEqual(Model.levelBlend(0.39, 0.4), { from: "low", to: "low", t: 0 })
  // threshold clamps at 60% so a silly value still leaves a ramp
  assert.deepEqual(Model.levelBlend(0.95, 0.9), { from: "full", to: "full", t: 0 })
  assert.deepEqual(Model.levelBlend(0.5, "nope"), { from: "mid", to: "low", t: 0 }, "bad threshold falls back to 20")
  assert.deepEqual(Model.levelBlend(NaN, 0.2), { from: "low", to: "low", t: 0 })
  assert.deepEqual(Model.levelBlend(7, 0.2), { from: "full", to: "full", t: 0 })
})

test("rgb ↔ hsv round-trips and marks grey as hueless", () => {
  const blue = { r: 0x7d / 255, g: 0x82 / 255, b: 0xd9 / 255 }
  const hsv = Model.rgbToHsv(blue)
  assert.ok(hsv.h > 0.63 && hsv.h < 0.67, "periwinkle sits around 235°")
  const back = Model.hsvToRgb(hsv.h, hsv.s, hsv.v)
  for (const k of ["r", "g", "b"]) assert.ok(Math.abs(back[k] - blue[k]) < 1e-9, k)
  assert.equal(Model.rgbToHsv({ r: 0.5, g: 0.5, b: 0.5 }).h, -1)
  assert.deepEqual(Model.hsvToRgb(0, 0, 1), { r: 1, g: 1, b: 1 })
})

test("mixRgb walks the wheel downward: blue → green → yellow → orange → red", () => {
  const blue = { r: 0x7d / 255, g: 0x82 / 255, b: 0xd9 / 255 }
  const yellow = { r: 0xe9 / 255, g: 0xbb / 255, b: 0x4f / 255 }
  const red = { r: 0xed / 255, g: 0x5b / 255, b: 0x5a / 255 }
  assert.deepEqual(Model.mixRgb(blue, yellow, 0), blue)
  assert.deepEqual(Model.mixRgb(blue, yellow, 1), yellow)
  const half = Model.mixRgb(blue, yellow, 0.5)
  assert.ok(half.g > half.r && half.g > half.b, "halfway from blue to yellow is green, not grey or magenta")
  const orange = Model.mixRgb(yellow, red, 0.5)
  assert.ok(orange.r > orange.g && orange.g > orange.b, "halfway from yellow to red is orange")
  // an achromatic end borrows the other's hue instead of spinning
  const greyToRed = Model.mixRgb({ r: 0.6, g: 0.6, b: 0.6 }, red, 0.5)
  assert.ok(greyToRed.r > greyToRed.g && greyToRed.r > greyToRed.b)
  // both grey: stays grey
  const grey = Model.mixRgb({ r: 0.2, g: 0.2, b: 0.2 }, { r: 0.8, g: 0.8, b: 0.8 }, 0.5)
  assert.ok(Math.abs(grey.r - 0.5) < 1e-9 && Math.abs(grey.g - 0.5) < 1e-9)
  // t outside 0..1 clamps; missing colours do not throw
  assert.deepEqual(Model.mixRgb(blue, yellow, 4), yellow)
  assert.deepEqual(Model.mixRgb(undefined, undefined, 0.5), { r: 0, g: 0, b: 0 })
})

test("previewState: a look at any state, off clears it", () => {
  assert.deepEqual(Model.previewState("out", 35), { mode: "out", fraction: 0.35, watts: 18 })
  assert.deepEqual(Model.previewState("IN", "70"), { mode: "in", fraction: 0.7, watts: 45 })
  assert.deepEqual(Model.previewState("hold", 80), { mode: "hold", fraction: 0.8, watts: 0 })
  assert.deepEqual(Model.previewState("full", 12), { mode: "full", fraction: 1, watts: 0 }, "full is full")
  assert.deepEqual(Model.previewState("out", 250), { mode: "out", fraction: 1, watts: 18 })
  assert.deepEqual(Model.previewState("out", "junk"), { mode: "out", fraction: 0.5, watts: 18 })
  assert.equal(Model.previewState("off", 0), null)
  assert.equal(Model.previewState("", 50), null)
  assert.equal(Model.previewState("sideways", 50), null)
})

test("signedWatts: up is in, down is out, flat is parked", () => {
  assert.equal(Model.signedWatts("in", 45.2), 45.2)
  assert.equal(Model.signedWatts("out", 18.3), -18.3)
  assert.equal(Model.signedWatts("out", -18.3), -18.3, "sign comes from mode, never the input")
  assert.equal(Model.signedWatts("hold", 3), 0)
  assert.equal(Model.signedWatts("full", 3), 0)
  assert.equal(Model.signedWatts("in", "x"), 0)
})

test("pipPeriod speeds up with watts and floors at 40%", () => {
  assert.equal(Model.pipPeriod(0, 1500), 1500)
  assert.equal(Model.pipPeriod(30, 1500), 1050)
  assert.equal(Model.pipPeriod(60, 1500), 600)
  assert.equal(Model.pipPeriod(200, 1500), 600, "clamped above 60 W")
  assert.equal(Model.pipPeriod(0, 0), 1500, "bad base falls back")
})

test("formatters", () => {
  assert.equal(Model.formatWatts(18.34), "18.3 W")
  assert.equal(Model.formatWatts(-18.34), "18.3 W")
  assert.equal(Model.formatWatts(0), "0 W")
  assert.equal(Model.formatWatts(45, 0), "45 W")
  assert.equal(Model.formatWatts("x"), "—")
  assert.equal(Model.formatDuration(3.4 * 3600), "3h 24m")
  assert.equal(Model.formatDuration(48 * 60), "48m")
  assert.equal(Model.formatDuration(7200), "2h")
  assert.equal(Model.formatDuration(3599.9), "1h", "59.99 min rounds up cleanly")
  assert.equal(Model.formatDuration(0), "—")
  assert.equal(Model.formatVolts(16.625), "16.6 V")
  assert.equal(Model.formatVolts(0), "—")
  assert.equal(Model.formatWattHours(66.851), "66.9 Wh")
  assert.equal(Model.formatWattHours(60), "60 Wh")
})

test("healthPercent and normalizePercent", () => {
  assert.equal(Model.healthPercent(66.851, 66.851), 100)
  assert.equal(Model.healthPercent(50, 66.851), 75)
  assert.equal(Model.healthPercent(0, 66.851), -1)
  assert.equal(Model.healthPercent(70, 0), -1)
  assert.equal(Model.healthPercent(80, 66), 100, "clamped")
  assert.equal(Model.normalizePercent(0.93), 93)
  assert.equal(Model.normalizePercent(93), 93)
  assert.equal(Model.normalizePercent(-1), -1)
})

test("parseSysfs: vic's BAT0 (energy_* in micro units)", () => {
  const raw = "power_now\t16616000\nvoltage_now\t16625000\nstatus\tDischarging\nenergy_full\t66851000\nenergy_full_design\t66851000\n"
  const s = Model.parseSysfs(raw)
  assert.equal(s.watts, 16.616)
  assert.equal(s.volts, 16.625)
  assert.equal(s.status, "discharging")
  assert.equal(s.full, 66.851)
  assert.equal(s.fullDesign, 66.851)
})

test("parseSysfs: charge_* cells fall back to current × voltage", () => {
  const raw = "current_now\t1500000\nvoltage_now\t12000000\ncharge_full\t4000000\ncharge_full_design\t5000000\n"
  const s = Model.parseSysfs(raw)
  assert.equal(s.watts, 18)
  assert.equal(s.full, 4)
  assert.equal(s.fullDesign, 5)
  assert.deepEqual(Model.parseSysfs(""), {})
})

test("pushSample returns a fresh capped array", () => {
  const a = [1, 2, 3]
  const b = Model.pushSample(a, 4, 3)
  assert.deepEqual(a, [1, 2, 3], "input untouched")
  assert.deepEqual(b, [2, 3, 4])
  assert.deepEqual(Model.pushSample(null, 7, 2), [7])
  assert.deepEqual(Model.pushSample([1], "x", 2), [1, 0])
})

test("traceScale picks the smallest nice step above the peak, never below the floor", () => {
  assert.equal(Model.traceScale([], 10), 10)
  assert.equal(Model.traceScale([2, -3], 10), 10)
  assert.equal(Model.traceScale([18.3, -12], 10), 20)
  assert.equal(Model.traceScale([-45], 10), 45)
  assert.equal(Model.traceScale([-45.2], 10), 60, "a hair over the step goes to the next one")
  assert.equal(Model.traceScale([700], 10), 720)
  assert.equal(Model.peakWatts([1, -9, 4]), 9)
})

test("statusLine and tooltip", () => {
  assert.equal(Model.statusLine("in", 45.2, ""), "Charging · 45.2 W in")
  assert.equal(Model.statusLine("out", 18.3, ""), "On battery · 18.3 W out")
  assert.equal(Model.statusLine("hold", 0, "80%"), "Holding at 80%")
  assert.equal(Model.statusLine("hold", 0, ""), "Holding")
  assert.equal(Model.statusLine("full", 0, ""), "Fully charged · on AC")
  assert.equal(Model.statusLine("none", 0, ""), "")
  assert.equal(Model.tooltip("out", 92, 18.3, "3h 24m", ""), "On battery 92%  ·  18.3 W out  ·  3h 24m left")
  assert.equal(Model.tooltip("in", 40, 45, "48m", ""), "Charging 40%  ·  45 W in  ·  48m to full")
  assert.equal(Model.tooltip("in", 40, 45, "—", ""), "Charging 40%  ·  45 W in", "unknown time is dropped")
  assert.equal(Model.tooltip("hold", 80, 0, "", "80%"), "Holding at 80%")
  assert.equal(Model.tooltip("full", 100, 0, "", ""), "Fully charged  ·  on AC")
})

test("glyph keys, next profile, sysfs path, upower seconds", () => {
  assert.equal(Model.laneKey("in"), "plug")
  assert.equal(Model.laneKey("hold"), "plug")
  assert.equal(Model.laneKey("out"), "laptop")
  assert.equal(Model.laneKey("none"), "")
  assert.equal(Model.trendKey("in"), "arrowUp")
  assert.equal(Model.trendKey("out"), "arrowDown")
  assert.equal(Model.trendKey("full"), "")
  assert.equal(Model.nextProfile(["power-saver", "balanced", "performance"], "balanced"), "performance")
  assert.equal(Model.nextProfile(["power-saver", "balanced", "performance"], "performance"), "power-saver")
  assert.equal(Model.nextProfile(["a"], "zzz"), "a", "unknown active starts at the top")
  assert.equal(Model.nextProfile([], "a"), "")
  assert.equal(Model.sysfsPath("BAT0"), "/sys/class/power_supply/BAT0")
  assert.equal(Model.sysfsPath("/sys/class/power_supply/BAT1"), "/sys/class/power_supply/BAT1")
  assert.equal(Model.sysfsPath(""), "/sys/class/power_supply/BAT0")
  assert.equal(Model.upowerSeconds(device(), "out"), 3.4 * 3600)
  assert.equal(Model.upowerSeconds(device({ timeToFull: 2880 }), "in"), 2880)
  assert.equal(Model.upowerSeconds(device(), "hold"), 0)
})

test("stock model survives untouched", () => {
  assert.equal(Model.modeLabel(device(), true, states), "On battery")
  // Stock's ladder: floor(0.92 * 10) = 9, the top rung.
  assert.equal(Model.batteryIcon(device({ percentage: 0.92 }), true, states), "󰁹")
  assert.equal(Model.batteryIcon(device({ percentage: 0.85 }), true, states), "󰂂")
  assert.equal(Model.batteryIcon(device({ percentage: 0.85, state: states.Charging }), false, states), "󰂋")
  assert.deepEqual(Model.parseProfiles("power-saver\t0\nbalanced\t1\nperformance\t0\n", 0),
    { profiles: ["power-saver", "balanced", "performance"], activeProfile: "balanced", profileIndex: 0 })
  assert.equal(Model.selectProfileIndex(2, 1, ["a", "b", "c"]), 2)
})
