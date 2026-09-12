#!/usr/bin/env bash
# Drives the LIVE widget over IPC. Skips cleanly when no shell is running.
# Fails against a hot-reloaded zombie (the old widget answers with stale
# code) — restart the shell before trusting a red result.
#
#   test/panel-test.sh
set -uo pipefail

fails=0
check() {
  if eval "$2"; then
    echo "  ok    $1"
  else
    echo "  FAIL  $1"
    fails=$((fails + 1))
  fi
}

if ! omarchy-shell shell ping >/dev/null 2>&1; then
  echo "  skip  no running omarchy shell"
  exit 0
fi

targets=$(qs ipc -n -p "${OMARCHY_PATH:-/usr/share/omarchy}/shell" show 2>/dev/null)
check "exactly one omarchy.power IPC target" '[[ $(grep -c "^target omarchy.power" <<<"$targets") -eq 1 ]]'
check "status() is exposed" 'grep -A12 "^target omarchy.power" <<<"$targets" | grep -q "function status()"'

status=$(omarchy-shell omarchy.power status 2>/dev/null)
check "status() returns JSON from pi.power" '[[ $(jq -r .plugin <<<"$status" 2>/dev/null) == "pi.power" ]]'
mode=$(jq -r .mode <<<"$status" 2>/dev/null)
check "mode is one of in/out/hold/full ($mode)" '[[ $mode =~ ^(in|out|hold|full)$ ]]'
pct=$(jq -r .percent <<<"$status" 2>/dev/null)
check "percent 0..100 ($pct)" '[[ $pct =~ ^[0-9]+$ ]] && (( pct >= 0 && pct <= 100 ))'
check "at least one rate sample" '(( $(jq -r .samples <<<"$status" 2>/dev/null) >= 1 ))'
check "profiles known" '(( $(jq -r ".profiles | length" <<<"$status" 2>/dev/null) >= 1 ))'
check "atoms in flight in the bar ($(jq -r .atoms <<<"$status" 2>/dev/null))" '(( $(jq -r .atoms <<<"$status" 2>/dev/null) >= 1 ))'
check "glints armed ($(jq -r .glints <<<"$status" 2>/dev/null))" '(( $(jq -r .glints <<<"$status" 2>/dev/null) >= 1 ))'
stops=$(jq -r '.stops | join(" ")' <<<"$status" 2>/dev/null)
check "three ramp stops in use ($stops)" '[[ $(jq -r ".stops | length" <<<"$status" 2>/dev/null) -eq 3 ]]'
check "vivid is a boolean ($(jq -r .vivid <<<"$status" 2>/dev/null))" '[[ $(jq -r .vivid <<<"$status" 2>/dev/null) =~ ^(true|false)$ ]]'
hum=$(jq -r .hum <<<"$status" 2>/dev/null)
humming=$(jq -r .humming <<<"$status" 2>/dev/null)
check "hum is a boolean ($hum)" '[[ $hum =~ ^(true|false)$ ]]'
label=$(jq -r .label <<<"$status" 2>/dev/null)
cellw=$(jq -r .cellWidth <<<"$status" 2>/dev/null)
check "label is a boolean ($label)" '[[ $label =~ ^(true|false)$ ]]'
check "bar cell has a width ($cellw px)" '[[ $cellw =~ ^[0-9]+$ ]] && (( cellw > 0 ))'

# Charge limit. Only asserted when the machine actually exposes a threshold;
# a laptop whose EC has none (or whose firmware no driver knows) must report
# unsupported rather than a fake zero.
limsup=$(jq -r .chargeLimitSupported <<<"$status" 2>/dev/null)
lim=$(jq -r .chargeLimit <<<"$status" 2>/dev/null)
check "chargeLimitSupported is a boolean ($limsup)" '[[ $limsup =~ ^(true|false)$ ]]'
if [[ $limsup == true ]]; then
  check "charge limit in 50..100 ($lim)" '[[ $lim =~ ^[0-9]+$ ]] && (( lim >= 50 && lim <= 100 ))'
  check "no charge-limit error ($(jq -r .chargeLimitError <<<"$status"))" '[[ -z $(jq -r ".chargeLimitError" <<<"$status") ]]'
  sysfs_lim=$(cat /sys/class/power_supply/BAT*/charge_control_end_threshold 2>/dev/null | head -1)
  if [[ -n $sysfs_lim ]]; then
    expect=$sysfs_lim; (( expect <= 0 )) && expect=100
    check "widget agrees with the kernel (sysfs=$sysfs_lim widget=$lim)" '[[ $lim -eq $expect ]]'
  fi
  # The limit must also be saved, or it lapses on the next cold boot.
  saved=$(jq -r .chargeLimitSaved <<<"$status" 2>/dev/null)
  unsaved=$(jq -r .chargeLimitUnsaved <<<"$status" 2>/dev/null)
  conf=$(sed -n 's/^CHARGE_LIMIT=\([0-9]\{1,3\}\).*/\1/p' /etc/default/power-pulse-charge-limit 2>/dev/null | tail -1)
  if [[ -n $conf ]]; then
    check "widget knows the saved value (conf=$conf widget=$saved)" '[[ $saved -eq $conf ]]'
    check "live limit matches the saved one (unsaved=$unsaved)" '[[ $unsaved == false ]]'
    check "boot restore service is enabled" 'systemctl is-enabled power-pulse-charge-limit.service >/dev/null 2>&1'
  else
    echo "  skip  no /etc/default/power-pulse-charge-limit (boot restore not installed)"
  fi
else
  check "unsupported machine reports limit 0" '[[ $lim -eq 0 ]]'
fi
if [[ $mode == full && $hum == true ]]; then
  check "a full cell with hum on is humming" '[[ $humming == true ]]'
else
  check "not humming unless full with hum on (mode=$mode hum=$hum)" '[[ $humming == false ]]'
fi

# Cross-check the mode against the kernel, which does not know about this plugin.
if [[ -r /sys/class/power_supply/BAT0/status ]]; then
  kstatus=$(</sys/class/power_supply/BAT0/status)
  case $kstatus in
    Discharging) check "kernel says $kstatus, widget says $mode" '[[ $mode == out ]]' ;;
    Charging) check "kernel says $kstatus, widget says $mode" '[[ $mode == in || $mode == hold ]]' ;;
    Full) check "kernel says $kstatus, widget says $mode" '[[ $mode == full || $mode == hold ]]' ;;
    *) echo "  skip  kernel status '$kstatus' has no fixed expectation" ;;
  esac
fi

# The preview paints a state without touching the battery; the level colour
# it reports must move along the ramp as the percent drops.
pv=$(omarchy-shell omarchy.power preview out 35 2>/dev/null)
check "preview out 35 takes" '[[ $(jq -r .preview <<<"$pv") == out && $(jq -r .mode <<<"$pv") == out && $(jq -r .percent <<<"$pv") == 35 ]]'
c35=$(jq -r .levelColor <<<"$pv")
c95=$(omarchy-shell omarchy.power preview out 95 2>/dev/null | jq -r .levelColor)
c10=$(omarchy-shell omarchy.power preview out 10 2>/dev/null | jq -r .levelColor)
check "levelColor is a colour ($c95 → $c35 → $c10)" '[[ $c95 =~ ^#[0-9a-f]{6,8}$ && $c35 =~ ^#[0-9a-f]{6,8}$ && $c10 =~ ^#[0-9a-f]{6,8}$ ]]'
check "levelColor changes along the ramp" '[[ $c95 != "$c35" && $c35 != "$c10" ]]'
check "10% on battery is low" '[[ $(omarchy-shell omarchy.power status | jq -r .low) == true ]]'
after=$(omarchy-shell omarchy.power preview off 0 2>/dev/null)
check "preview off returns to the battery" '[[ $(jq -r .preview <<<"$after") == "" && $(jq -r .mode <<<"$after") == "$mode" ]]'

omarchy-shell omarchy.power open >/dev/null 2>&1
sleep 0.5
check "open() opens the panel" '[[ $(omarchy-shell omarchy.power status | jq -r .opened) == true ]]'
omarchy-shell omarchy.power close >/dev/null 2>&1

echo
(( fails == 0 )) && echo "panel-test: all green" || echo "panel-test: $fails failure(s)"
exit $(( fails > 0 ))
