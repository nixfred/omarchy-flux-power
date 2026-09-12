# Power Pulse

Formerly Flux Power. The plugin id is still `pi.power`, so an existing `shell.json` entry keeps working.

An Omarchy shell plugin that replaces the stock battery widget with a glowing flux cell you can read from across the room: sparks ride **into** the cell while it charges, **out** of it on battery, and the whole thing turns red when it is running low.

![status](https://img.shields.io/badge/omarchy-plugin-blue) ![license](https://img.shields.io/badge/license-MIT-green)

## What it does differently

Stock draws a Nerd Font battery rune and, optionally, `92%`. Power Pulse:

- **A glowing cell in the bar whose colour is its charge.** The battery is drawn from real rectangles with the charge as a fill, wrapped in a GPU glow. Outline, fill, halo and sparks all wear the level colour: the theme's **blue** when full, sliding round the hue wheel (through green) to **yellow** about the middle and to **red** by the low threshold — on AC or on battery. The glow breathes — fast while charging, slow on battery, a throb when low. The bolt at the far end of the wire stays accent: it is the wall's energy, not the cell's.
- **A stream of atoms that shows direction.** Charging, glowing atoms are born at the bolt in the lane, cross into the cell and die at the fill's leading edge, rising as they go, while a shimmer sweeps the fill and its edge flares. On battery they run the other way — born at the fill, out through the lane, sinking and fading. Every atom has its own size, band, speed and rhythm, so it reads as a current rather than a convoy, and the pace follows the wattage.
- **Glints.** Four-point sparkles pop and spin wherever the atoms are landing or leaving, a little outside the outline too, like sparks flying off.
- **A full cell brims.** Parked at 100% on the wall there is no current to show, so the atoms rest — but the halo swells harder and the glints keep crackling, slower, because the energy is in there. A docked laptop spends most of its day here; it should not look switched off.
- **The number inside the cell.** With `showPercentage` on, the charge is written as digits over the fill: dark on the filled part, foreground past the fill's edge, so it reads on blue, yellow and red alike with no outline or box round it. The cell grows a little to hold it and the widget takes one slot instead of two. No `%`: a number inside a battery is a percentage already. The atoms already say which way the power is going, so the bar carries no arrow; the panel's percentage keeps its up/down arrow.
- **A charge-limit slider.** Stop charging at a ceiling so a docked laptop is not parked at 100% all day, which is what ages a lithium pack fastest. The slider runs 50-100% in 5-point notches; the top notch is "charge to full", because the kernel interface has no separate off switch. The line under it names the resume point as well as the ceiling, since a limit of 80 does not hold at exactly 80: the EC stops there and waits until the pack falls to the start threshold before topping up, so the charge drifts in a band. The whole section is absent on a machine whose kernel exposes no threshold, rather than present and dead.
- **A tooltip that answers the question.** `On battery 92%  ·  18.3 W out  ·  3h 24m left`.
- **The panel scales the same cell up**, with a plug or laptop at the far end of the wire depending on which way the power is going, and a lock over a cell parked at a charge threshold.
- **The last hour as bars off a centre line.** Up is in, down is out, flat is parked. Sampled from UPower every 30 seconds whether the panel is open or not, so it has a past the first time you look, and persisted across shell hot-reloads.
- **Live wattage.** With the panel open a sysfs probe reads `power_now` every two seconds, so the number is what the cell is doing *now*, not UPower's 30-second-old estimate. Capacity, health (of design capacity), cycles and voltage sit beside it.
- **A status line that holds still.** Stock rotated nine joke phrases ("Sucking volts", "Munching reserves") through the subtitle every 2.8 seconds. This says `CHARGING · 45.2 W IN` and only the number moves.

Everything else — the power-profile picker, keyboard navigation, `omarchy-shell omarchy.power open`, right-click to toggle the percentage — is stock behaviour, deliberately preserved. Middle-click cycles the power profile.

## Install

```bash
omarchy plugin add https://github.com/nixfred/power-pulse --enable
```

On `dex` it is installed as plain files (no `.git`), so Omarchy's plugin updater leaves it alone; `version-lock.json` records the source commit and the SHA-256 of every runtime file that is live there. Deploy by copying the six runtime files plus the lock into `~/.config/omarchy/plugins/pi.power/` and running `omarchy restart shell`.

The manifest declares `clonedFrom: omarchy.power`, so enabling it takes the stock widget's place in the bar and the shell routes `omarchy.power` IPC calls (the control centre uses them) to this plugin.

## Settings

Inline on the bar entry in `~/.config/omarchy/shell.json`:

| Key | Default | What |
|---|---|---|
| `showPercentage` | `false` | The charge as digits inside the cell. Right-click toggles it |
| `showTrend` | `true` | The up/down arrow beside the panel's percentage |
| `sizzle` | `true` | Every animation, bar and panel. `false` is a still picture |
| `barGlow` | `true` | The glow and sparks in the bar specifically |
| `sparkDensity` | `1` | How many atoms and glints are in flight, `0`–`3`. `0` keeps the glow and stills the stream |
| `sparkle` | `true` | The four-point glints around the atoms |
| `hum` | `true` | A cell parked full keeps glowing hard and crackling with glints. `false` lets it simmer quietly, atoms and glints off until power moves |
| `lowThreshold` | `20` | Percent at which "on battery" turns urgent, and where the ramp reaches its bottom colour |
| `fullColor` | `"blue"` | The ramp's top stop. A `colors.toml` key (`blue`, `cyan`, `green`, …), a shell role (`accent`, `urgent`, `foreground`, `muted`) or a literal `#rrggbb` |
| `midColor` | `"yellow"` | The middle stop, reached at 50% (or 15 points above the threshold, whichever is higher) |
| `lowColor` | `"red"` | The bottom stop |
| `vivid` | `true` | Guarantee every stop can be seen. A stop that stands out from the bar and is a colour is used as it is; a dull one keeps its hue but gains saturation and brightness until it glows. `false` wears the theme verbatim, dull or not |

## The charge limit

The slider writes the kernel's own `charge_control_end_threshold`, so it works on any laptop whose driver exposes one (ThinkPads, most ASUS, Framework, and MSI via `msi-ec`). Read it or set it without the panel:

```bash
omarchy-shell omarchy.power status | jq '{chargeLimitSupported, chargeLimit, chargeLimitStart}'
omarchy-shell omarchy.power chargeLimit 80     # 100 = charge to full
./charge-limit get                             # end<TAB>start, or nothing if unsupported
./charge-limit set 80
```

`charge_control_end_threshold` is root-owned, so the bundled `charge-limit` helper escalates: a direct write first (works if a udev rule has made the attribute group-writable), then `sudo -n`, then `pkexec`. It reads the value back after writing and fails loudly if the driver reports something else, because a limit that silently did not apply is worse than an error.

### Making it survive a reboot

The live ceiling is a byte in EC RAM. On some boards that survives a warm reboot and on none is it guaranteed to survive a cold one, so the limit has to be re-applied at boot or it quietly lapses — the exact failure the limit exists to prevent, and invisible until the pack has sat at 100% for a week.

Two pieces, both root-owned:

- `/etc/default/power-pulse-charge-limit` holds `CHARGE_LIMIT=80`. The slider rewrites it on every change, so boot restores what you last chose. Setting the sysfs value by hand without updating this file is the one way to desync them, and the panel says so when it happens: *"not saved for reboot (boot would restore 80%)"* in the urgent colour.
- `power-pulse-charge-limit.service`, a oneshot that runs `/usr/local/bin/power-pulse-charge-limit-apply` after `systemd-modules-load.service`. It waits up to 15 s for the driver's battery hook to create the attribute, writes the saved value, reads it back, and exits 0 with an explanation on a machine that has no threshold at all, so a missing driver never blocks a boot.

`status()` reports `chargeLimitSaved` and `chargeLimitUnsaved` alongside the live value, and `test/panel-test.sh` asserts the two agree and that the service is enabled.

### MSI laptops with firmware no driver knows yet

`msi-ec` keys off the EC firmware string and refuses anything not on its list, so a new model has no threshold file at all. On **gus** (MSI Crosshair 16 Max HX, MS-2652, EC `2652EMS1.303`) neither the in-tree driver nor upstream knows that firmware. The out-of-tree module takes a firmware override, and `182KIMS1.113` (the 2025 Titan/Crosshair family) is the closest relative:

```bash
yay -S msi-ec-dkms-git
sudo modprobe -r msi_ec
sudo modprobe msi-ec firmware=182KIMS1.113
```

That was **verified on this board, not assumed**: writing 60 / 80 / 100 to the threshold produced EC byte `0xd7` = `bc` / `d0` / `e4`, exactly `percent | BIT(7)`, with the start threshold trailing the end by 10. Only the charge threshold is trusted from a borrowed config. The same config's `fan_mode`, `shift_mode` and `cooler_boost` addresses are **unverified on this board — do not write them.**

The module will not autoload, because its DMI alias only binds when the firmware whitelist matches, so boot needs to be told twice — load it, and load it with the override:

```bash
printf 'options msi-ec firmware=182KIMS1.113\n' | sudo tee /etc/modprobe.d/msi-ec.conf
printf 'msi-ec\n' | sudo tee /etc/modules-load.d/msi-ec.conf
```

Verified on gus by tearing the whole thing down and letting systemd rebuild it: unload `msi_ec` (the threshold file disappears), change the saved value, `systemctl restart systemd-modules-load.service` (the module comes back *with* the override), then start the restore unit — the new value lands in the EC. That is the boot path, run in the boot order.

```json
{ "id": "pi.power", "showPercentage": true, "lowThreshold": 15 }
{ "id": "pi.power", "fullColor": "accent", "midColor": "#f2c14e", "lowColor": "urgent" }
```

The stops come from the active theme's `~/.local/state/omarchy/current/theme/colors.toml`, so they follow a theme switch. A theme that lacks a key falls back to `accent` / `#e9bb4f` / `urgent`. The blend walks the hue wheel downward, which is why blue → yellow passes through green rather than through grey; pick two stops with adjacent hues if you want a shorter trip.

Not every theme's blue is a glow. 2-haxorz, for one, ships `blue = "#2b5e8f"` on a `#0b1b2b` bar (2.6:1, and the same navy as its accent), and a cell wearing that faithfully is invisible: no halo, no colour, the stock glyph in all but name. `vivid` is the fix. It measures each stop against the bar's actual background and leaves alone anything that both reaches 4.5:1 and is a colour rather than a tinted grey (saturation 0.25 or more): ethereal, tokyo-night, nord, gruvbox and everforest all pass untouched, pastels included. A stop that fails either test keeps its hue, has its saturation lifted to 0.55 and its brightness walked away from the bar until it reaches 4.5:1: brighter on a dark bar, darker on a light one. 2-haxorz's yellow and red are the tinted-grey case, an olive and a dusty rose at 0.23 whose halo is a smudge. Grey and near-grey stops (0.15 or under) stay grey, so a monochrome theme keeps its restraint. `status()` reports the three stops actually in use.

## IPC

```bash
omarchy-shell omarchy.power toggle            # the panel
omarchy-shell omarchy.power togglePercentage
omarchy-shell omarchy.power cycleProfile
omarchy-shell omarchy.power status            # JSON: mode, percent, watts, low, levelColor, samples, profile…
omarchy-shell omarchy.power preview out 35    # paint "on battery, 35%" for 30 s without draining anything
omarchy-shell omarchy.power preview in 60     # …or charging at 60%; also hold <pct> and full
omarchy-shell omarchy.power preview off 0     # back to the real battery
```

The preview fakes only the picture (mode, level, wattage, and so the colour); the profile picker and the stats stay live. It is how the ramp gets looked at on a laptop that happens to be plugged in.

## Performance notes

Nothing here is rasterised per frame, a rule learned the hard way on an earlier plugin:

1. **The glow is a `MultiEffect` drop-shadow** of a hidden stencil. Its texture only changes when the fill level moves; the breath is one uniform (`shadowOpacity`).
2. **Sparks, shimmer and the edge flare are plain `Rectangle`s** animated on `x` / `y` / `opacity`, which the compositor interpolates for free.
3. **The trace `Canvas` repaints only when a sample lands** — every 30 seconds — never per frame. The ring on the newest bar is a scene-graph scale/opacity animation.
4. **The bar spawns no processes.** Direction, level and wattage in the bar come from UPower's push-updated D-Bus properties. The sysfs probe and `omarchy-battery-status` only run while the panel is open.

## Glyphs

`Glyphs.js` is **generated**, not hand-written. A wrong Nerd Font codepoint still exists in the font, so a presence check passes while the bar draws the wrong picture. Every row carries the Material Design glyph *name*, and `test/glyphs-test.py` re-resolves each name out of the `.ttf` cmap:

```bash
uv run --with fonttools python3 test/glyphs-test.py
```

## Verify

```bash
./check                 # model tests, QML syntax, manifest, glyph names
test/panel-test.sh      # drives the LIVE widget over IPC after a deploy
```

`./check` cannot see a QML binding error — those only surface at instantiation. After a QML change, deploy, restart the shell, run the panel test, and look at the bar.

## Files

| File | Role |
|---|---|
| `Panel.qml` | Bar button, panel, sampler, sysfs probe, IPC (stock lineage) |
| `FluxCell.qml` | The cell: glow, fill, shimmer, edge flare, sparks in / out. One component, bar and hero scale |
| `PowerTrace.qml` | The last hour as up/down bars, head pulse |
| `Model.js` | Stock model, untouched, plus the flux logic — pure functions, node-tested |
| `Glyphs.js` | Generated name → codepoint table |

## Credits

Cloned from and built on Omarchy's stock `omarchy.power` panel by [DHH / Omarchy](https://omarchy.org). MIT licensed.
