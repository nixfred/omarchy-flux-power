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

omarchy-shell omarchy.power open >/dev/null 2>&1
sleep 0.5
check "open() opens the panel" '[[ $(omarchy-shell omarchy.power status | jq -r .opened) == true ]]'
omarchy-shell omarchy.power close >/dev/null 2>&1

echo
(( fails == 0 )) && echo "panel-test: all green" || echo "panel-test: $fails failure(s)"
exit $(( fails > 0 ))
