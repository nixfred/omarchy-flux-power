import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Glyphs.js" as Glyphs

// Flux Power — Omarchy's stock power panel with a battery you can read from
// across the room. The bar draws a glowing flux cell: sparks ride into it
// while it charges, out of it on battery, red when it is running low. The
// panel scales the same cell up, adds an hour-long up/down power trace and
// the live in/out wattage, and keeps stock's power-profile picker and every
// keyboard binding exactly as they were.
//
// Settings (shell.json, inline on the bar entry):
//   showPercentage  stock — the number beside the cell     (default false)
//   showTrend       an up/down arrow beside the percentage  (default true)
//   sizzle          every animation, bar and panel          (default true)
//   barGlow         the glow and sparks in the bar          (default true)
//   lowThreshold    percent at which "out" turns urgent     (default 20)
Panel {
  id: root
  moduleName: "pi.power"
  // Stock's IPC name is kept so `omarchy-shell omarchy.power open` (the
  // control centre uses it) keeps working after the clone swap. manageIpc is
  // off because this panel owns the single IpcHandler the target permits.
  ipcTarget: "omarchy.power"
  manageIpc: false

  property var batteryInfo: ({})
  property var sysInfo: ({})
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property bool cursorActive: false

  readonly property bool showPercentage: setting("showPercentage", false) === true
  readonly property bool showTrend: setting("showTrend", true) !== false
  readonly property bool sizzle: setting("sizzle", true) !== false
  readonly property bool barGlow: setting("barGlow", true) !== false
  readonly property int lowThreshold: {
    var v = Number(setting("lowThreshold", 20))
    return isFinite(v) ? Math.max(0, Math.min(100, Math.round(v))) : 20
  }
  readonly property bool animating: sizzle && opened
  readonly property bool barAnimating: sizzle && barGlow

  // The open-panel mark under the bar button spans the painted cell + number,
  // not the icon-sized fraction of the slot the bar would otherwise assume.
  readonly property real openPanelIndicatorWidth: !button.vertical ? content.width : 0

  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
  }

  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  function batteryIcon() {
    var device = UPower.displayDevice
    return Model.batteryIcon(device, root.discharging, upowerStates())
  }

  function profileIcon(name) {
    return Model.profileIcon(name)
  }

  // ---- Stock state ladder (unchanged) ----------------------------------------
  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive
  }
  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }
  readonly property bool chargeThresholdActive: {
    var device = UPower.displayDevice
    return Model.chargeThresholdActive(device, root.discharging, upowerStates())
  }
  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive
  readonly property real batteryFraction: {
    var d = UPower.displayDevice
    return Model.batteryFraction(d)
  }
  readonly property bool charging: {
    var d = UPower.displayDevice
    return d && d.isPresent && !UPower.onBattery && !root.batteryFlowIdle
  }

  // ---- Flux state --------------------------------------------------------------
  readonly property string flowMode: {
    var d = UPower.displayDevice
    return Model.flowMode(d, UPower.onBattery, upowerStates())
  }
  readonly property bool flowing: flowMode === "in" || flowMode === "out"
  readonly property bool low: Model.isLow(batteryFraction, flowMode, lowThreshold)
  readonly property int percent: Math.round(batteryFraction * 100)

  // UPower's rate is push-updated over D-Bus (free, ~30 s lag). While the
  // panel is open the sysfs probe below supplies the instantaneous number.
  readonly property real upowerWatts: {
    var d = UPower.displayDevice
    return d && d.isPresent ? Math.abs(Number(d.changeRate) || 0) : 0
  }
  readonly property real watts: (opened && sysInfo.watts !== undefined) ? sysInfo.watts : upowerWatts

  readonly property string timeText: {
    var d = UPower.displayDevice
    return Model.formatDuration(Model.upowerSeconds(d, root.flowMode))
  }
  readonly property string thresholdText: batteryInfo.threshold || ""
  readonly property string tooltipText: Model.tooltip(flowMode, percent, watts, timeText, thresholdText)
  readonly property string heroStatusText: Model.statusLine(flowMode, watts, thresholdText)

  readonly property int health: {
    var d = UPower.displayDevice
    if (d && d.isPresent && d.healthSupported) return Model.normalizePercent(d.healthPercentage)
    return Model.healthPercent(sysInfo.full, sysInfo.fullDesign)
  }
  readonly property real capacityWh: {
    var d = UPower.displayDevice
    var wh = d && d.isPresent ? Number(d.energyCapacity) : 0
    if (isFinite(wh) && wh > 0) return wh
    return sysInfo.full !== undefined ? Number(sysInfo.full) : 0
  }

  readonly property color flowColor: barCell.flowColor

  // ---- Rate history: the hour behind the trace --------------------------------
  // Sampled from UPower every 30 s whether or not the panel is open, so the
  // trace has a past the first time it is looked at. Persisted as JSON so a
  // shell hot-reload does not wipe the hour.
  readonly property int historyCapacity: 120
  property var rateHistory: []

  PersistentProperties {
    id: persisted
    reloadableId: "pi-power-flux"
    property string rateHistoryJson: ""
  }

  function sampleRate() {
    var d = UPower.displayDevice
    if (!d || !d.isPresent) return
    rateHistory = Model.pushSample(rateHistory, Model.signedWatts(root.flowMode, root.upowerWatts), historyCapacity)
    persisted.rateHistoryJson = JSON.stringify(rateHistory)
  }

  Timer {
    interval: 30000
    running: root.batteryPresent
    repeat: true
    triggeredOnStart: true
    onTriggered: root.sampleRate()
  }

  Component.onCompleted: {
    try {
      var saved = JSON.parse(persisted.rateHistoryJson || "[]")
      if (Array.isArray(saved) && saved.length > 0) rateHistory = saved.slice(-historyCapacity)
    } catch (e) {}
    // Profiles are fetched once up front so a middle-click cycles them before
    // the panel has ever been opened.
    if (!profilesProc.running) profilesProc.running = true
  }

  // ---- Refresh (stock cadence, minus the unused system-stats probe) -----------
  function refresh() {
    if (!batteryPresent) return
    if (!batteryProc.running) batteryProc.running = true
    if (!profilesProc.running) profilesProc.running = true
  }

  function updateBattery(raw) {
    var next = Model.parseKeyValue(raw)
    // Keep last known good data if a refresh briefly returns nothing — happens
    // around AC plug/unplug events. Avoids the section collapsing mid-transition.
    if (Object.keys(next).length === 0) return
    batteryInfo = next
  }

  function updateSysfs(raw) {
    var next = Model.parseSysfs(raw)
    if (Object.keys(next).length === 0) return
    sysInfo = next
  }

  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw, profileIndex)
    // Same guard as battery: preserve the last known profile list across
    // transient empty payloads so the buttons don't blink out.
    if (parsed.profiles.length === 0) return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    profileIndex = parsed.profileIndex
    if (opened && !cursorActive) {
      var idx = profiles.indexOf(activeProfile)
      if (idx >= 0) profileIndex = idx
    }
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    actionProc.command = ["omarchy-powerprofiles-set", root.discharging ? "battery" : "ac", profile]
    actionProc.running = true
  }

  function cycleProfile() {
    setProfile(Model.nextProfile(profiles, activeProfile))
  }

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  IpcHandler {
    target: "omarchy.power"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
    function cycleProfile() { root.cycleProfile() }
    function status(): string {
      return JSON.stringify({
        plugin: "pi.power",
        mode: root.flowMode,
        percent: root.percent,
        watts: root.watts,
        low: root.low,
        sizzle: root.sizzle,
        barGlow: root.barGlow,
        samples: root.rateHistory.length,
        profile: root.activeProfile,
        profiles: root.profiles,
        opened: root.opened
      })
    }
  }

  onOpenedChanged: {
    if (opened) {
      if (!batteryPresent) {
        close()
        return
      }

      refresh()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
    }
  }

  onBatteryPresentChanged: if (!batteryPresent) close()

  visible: batteryPresent
  implicitWidth: batteryPresent ? button.implicitWidth : 0
  implicitHeight: batteryPresent ? button.implicitHeight : 0

  Process {
    id: batteryProc
    command: ["omarchy-battery-status", "--shell"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateBattery(text) }
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateProfiles(text) }
  }

  // Instantaneous kernel telemetry for the open panel. UPower's rate lags by
  // tens of seconds; power_now is what the cell is doing right now.
  readonly property string sysfsPath: {
    var d = UPower.displayDevice
    return Model.sysfsPath(d ? d.nativePath : "")
  }

  Process {
    id: sysProc
    command: ["sh", "-c",
      "cd \"$1\" 2>/dev/null || exit 0; for f in power_now current_now voltage_now status energy_full energy_full_design charge_full charge_full_design; do [ -r \"$f\" ] && printf '%s\\t%s\\n' \"$f\" \"$(cat \"$f\")\"; done",
      "sh", root.sysfsPath]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateSysfs(text) }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  Timer {
    interval: 2000
    running: root.opened && root.batteryPresent
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!sysProc.running) sysProc.running = true
  }

  // ============================================================ bar widget ====
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // A vertical bar gets stock's glyph; the flux cell is a horizontal thing.
    labelVisible: vertical
    text: vertical ? root.batteryIcon() : ""
    fontSize: Style.bar.iconFont
    hasVisualContent: root.batteryPresent
    fixedWidth: vertical ? -1 : Math.ceil(content.implicitWidth + scaledHorizontalMargin * 2)
    fixedHeight: vertical ? Style.bar.iconSlot : -1
    tooltipText: root.tooltipText
    onPressed: function(b) {
      if (!root.batteryPresent) return
      if (b === Qt.RightButton) root.togglePercentage()
      else if (b === Qt.MiddleButton) root.cycleProfile()
      else root.toggle()
    }

    Row {
      id: content
      visible: !button.vertical
      anchors.centerIn: parent
      spacing: Style.space(5)

      FluxCell {
        id: barCell
        anchors.verticalCenter: parent.verticalCenter
        fraction: root.batteryFraction
        mode: root.flowMode
        watts: root.watts
        low: root.low
        animate: root.barAnimating
        glow: root.barGlow
        accent: Color.accent
        foreground: button.foreground
        urgent: button.activeColor
        muted: Color.muted
        fontFamily: button.fontFamily
      }

      Row {
        visible: root.showPercentage
        anchors.verticalCenter: parent.verticalCenter
        spacing: Math.max(1, Style.space(1))

        Text {
          readonly property string key: Model.trendKey(root.flowMode)
          visible: root.showTrend && key !== ""
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Glyphs.glyph(key)
          color: root.flowColor
          font.family: button.fontFamily
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering

          Behavior on color { ColorAnimation { duration: 220 } }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.percent + "%"
          color: root.low ? button.activeColor : button.foreground
          font.family: button.fontFamily
          font.pixelSize: Style.bar.iconFont
          renderType: Text.NativeRendering

          Behavior on color { ColorAnimation { duration: 220 } }
        }
      }
    }
  }

  // ================================================================= panel ====
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dx !== 0) root.selectProfileByDelta(dx)
        else if (dy !== 0) root.selectProfileByDelta(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateSelectedProfile()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: flux cell · title/status · percentage ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroCell.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          FluxCell {
            id: heroCell
            hero: true
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            fraction: root.batteryFraction
            mode: root.flowMode
            watts: root.watts
            low: root.low
            animate: root.animating
            glow: root.sizzle
            accent: Color.accent
            foreground: root.bar.foreground
            urgent: root.bar.urgent
            muted: Color.muted
            fontFamily: root.bar.fontFamily
          }

          Column {
            id: heroLabels
            anchors.left: heroCell.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Battery"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            // A status line that holds still. Stock rotated nine joke phrases
            // through here every 2.8 s; this reports what is actually happening
            // and only the wattage moves.
            Text {
              id: heroStatus
              textFormat: Text.PlainText
              text: root.heroStatusText.toUpperCase()
              color: root.flowing ? root.flowColor : Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width

              Behavior on color { ColorAnimation { duration: 220 } }
            }
          }

          Row {
            id: heroPercent
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              readonly property string key: Model.trendKey(root.flowMode)
              visible: root.showTrend && key !== ""
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: Glyphs.glyph(key)
              color: root.flowColor
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.heading
              renderType: Text.NativeRendering
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.percent + "%"
              color: root.low ? root.bar.urgent : root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.displayLarge
              font.bold: true

              Behavior on color { ColorAnimation { duration: 200 } }
            }
          }
        }

        // ---------- The last hour: up is in, down is out ----------
        Column {
          width: parent.width
          spacing: Style.space(4)

          Row {
            width: parent.width
            spacing: Style.space(8)

            Caption { text: "LAST HOUR" }
            Item { width: Style.space(4); height: 1 }
            Caption { text: Glyphs.glyph("arrowUp") + " IN"; color: Color.accent; opacity: 0.95 }
            Caption { text: Glyphs.glyph("arrowDown") + " OUT" }
            Item {
              width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[1].width
                - parent.children[2].implicitWidth - parent.children[3].implicitWidth
                - peakCaption.implicitWidth - parent.spacing * 5)
              height: 1
            }
            Caption {
              id: peakCaption
              text: "PEAK " + Model.formatWatts(Model.peakWatts(root.rateHistory), 0)
            }
          }

          PowerTrace {
            width: parent.width
            samples: root.rateHistory
            capacity: root.historyCapacity
            fullScale: Model.traceScale(root.rateHistory, 10)
            live: root.flowing
            animate: root.animating
            low: root.low
            accent: Color.accent
            foreground: root.bar.foreground
            urgent: root.bar.urgent
            muted: Color.muted
          }
        }

        // ---------- Stats ----------
        // Visibility is only gated by "we've ever loaded data" so the section
        // never collapses mid-transition (stock's reasoning, kept).
        Row {
          visible: root.batteryInfo.percentage !== undefined || root.sysInfo.watts !== undefined
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair {
              label: root.chargeThresholdActive ? "Charge limit" : (root.discharging ? "Time left" : "Time to full")
              value: root.chargeThresholdActive ? (root.batteryInfo.threshold || "—")
                : (root.batteryFlowIdle ? "—" : (root.batteryInfo.time || root.timeText))
            }
            InfoPair { label: "Capacity"; value: root.capacityWh > 0 ? Model.formatWattHours(root.capacityWh) : (root.batteryInfo.size || "—") }
            InfoPair { label: "Charge cycles"; value: root.batteryInfo.cycles || "—" }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair {
              label: root.flowMode === "in" ? "Flowing in" : (root.flowMode === "out" ? "Flowing out" : "Battery state")
              value: root.flowing ? Model.formatWatts(root.watts) : (root.chargeThresholdActive ? "Holding" : (root.batteryFull ? "Full" : "—"))
              valueColor: root.flowing ? root.flowColor : root.bar.foreground
            }
            InfoPair { label: "Health"; value: root.health >= 0 ? root.health + "%" : "—" }
            InfoPair { label: "Voltage"; value: Model.formatVolts(root.sysInfo.volts) }
          }
        }

        // ---------- Power profile picker (stock) ----------
        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "POWER PROFILE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.profiles.length > 0
              ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length
              : 0

            Repeater {
              model: root.profiles
              Button {
                required property var modelData
                required property int index
                width: profileRow.cellWidth
                iconText: root.profileIcon(String(modelData))
                iconSize: Style.font.title
                text: String(modelData).charAt(0).toUpperCase() + String(modelData).slice(1)
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.activeProfile === modelData
                hasCursor: root.cursorActive && root.profileIndex === index
                onClicked: root.setProfile(modelData)
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.profileIndex = index
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  component Caption: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.2
    renderType: Text.NativeRendering
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""
    property color valueColor: root.bar.foreground

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value; color: valueColor }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall

    Behavior on color { ColorAnimation { duration: 220 } }
  }
}
