// GENERATED TABLE — every codepoint here was resolved by NAME out of the
// JetBrainsMono Nerd Font cmap (see test/glyphs-test.py, which re-checks it).
//
// Never hand-type a codepoint into this file. The Material Design block is
// dense enough that a wrong number is almost always still *a* glyph, so a
// presence check passes while the bar draws popcorn where the bolt should be.
// Edit the `name`, run ./check, and let a missing name fail loudly.
var TABLE = {
  bolt:      { name: "md-lightning_bolt",        cp: 0xF140B },  // 󱐋 AC in the bar lane
  plug:      { name: "md-power_plug",            cp: 0xF06A5 },  // 󰚥 AC in the hero lane
  laptop:    { name: "md-laptop",                cp: 0xF0322 },  // 󰌢 the load, on battery
  arrowUp:   { name: "md-arrow_up_thin",         cp: 0xF19B2 },  // 󱦲 power going up
  arrowDown: { name: "md-arrow_down_thin",       cp: 0xF19B3 },  // 󱦳 power going out
  lock:      { name: "md-lock_outline",          cp: 0xF0341 },  // 󰍁 charge threshold holding
  health:    { name: "md-battery_heart_outline", cp: 0xF1210 },  // 󱈐
  clock:     { name: "md-clock_outline",         cp: 0xF0150 },  // 󰅐
  counter:   { name: "md-counter",               cp: 0xF0199 },  // 󰆙
  wave:      { name: "md-sine_wave",             cp: 0xF095B }   // 󰥛
}

function glyph(key) {
  var entry = TABLE[key]
  return entry ? String.fromCodePoint(entry.cp) : ""
}

if (typeof module !== "undefined") {
  module.exports = { TABLE: TABLE, glyph: glyph }
}
