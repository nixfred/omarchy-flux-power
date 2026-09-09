import QtQuick
import QtQuick.Effects
import qs.Commons
import "Model.js" as Model
import "Glyphs.js" as Glyphs

// The flux cell. A battery drawn from plain rectangles, wrapped in a GPU glow
// the colour of its charge, with sparks that ride INTO the cell while it
// charges (rising) and OUT of it while it drains (sinking).
//
// The colour IS the level: blue when full, sliding round the hue wheel to
// yellow about the middle and to red by the low threshold — outline, fill,
// halo and sparks together, on AC or off it. The lane bolt stays accent: it
// is the wall's energy, not the cell's.
//
// One component, two scales: `hero: false` is the bar version, which can
// carry the charge as digits inside the cell, `hero: true` is the panel
// version with a wider lane and the percentage beside it.
//
// Motion budget — nothing here is rasterised per frame. The glow is a
// MultiEffect drop-shadow of a hidden stencil whose texture only changes when
// the fill level moves; the breath is one uniform (shadowOpacity). Sparks,
// the shimmer and the edge flare are Rectangles animated on x / y / opacity,
// which the compositor interpolates for free.
Item {
  id: root

  property real fraction: 0
  property string mode: "none"        // none | in | out | hold | full
  property real watts: 0              // magnitude — sets spark speed
  property bool low: false
  property bool animate: true
  property bool glow: true
  property bool hero: false
  property color accent: Color.accent
  property color foreground: Color.foreground
  property color urgent: Color.urgent
  property color muted: Color.muted
  property string fontFamily: Style.font.family
  // What sits behind the widget. The digits inside the cell wear this as an
  // outline so they read over the fill whatever colour the ramp is at.
  property color background: Color.bar.background

  // The number inside the cell (bar only). One slot for the battery instead
  // of two: the cell grows a little and the charge is written over the fill.
  property bool label: false
  readonly property bool labelled: label && !hero

  // The ramp's three stops and where its red end sits (0..1). Panel.qml
  // resolves these from the theme's colors.toml and shell.json.
  property color fullColor: accent
  property color midColor: "#e9bb4f"
  property color lowColor: urgent
  property real lowFraction: 0.2

  property real cellWidth: hero ? Style.space(100) : (labelled ? Style.space(30) : Style.space(24))
  property real cellHeight: hero ? Style.space(38) : (labelled ? Style.space(14) : Style.space(11))
  property real laneWidth: hero ? Style.space(30) : Style.space(13)

  readonly property real nubWidth: hero ? Style.space(4) : Math.max(2, Style.spaceReal(2))
  readonly property real nubHeight: Math.round(cellHeight * 0.45)
  readonly property real strokeWidth: hero ? Math.max(2, Style.spaceReal(2)) : Math.max(1, Style.spaceReal(1.25))
  // With the number inside, the fill sits flush against the outline: the gap
  // that gives the hero cell its inner glow reads as a box round the digits
  // at bar scale.
  readonly property real inset: strokeWidth + (hero ? Style.space(3) : (labelled ? 0 : Math.max(1, Style.spaceReal(1.5))))
  readonly property real pipSize: hero ? Style.space(5) : Math.max(3, Style.spaceReal(2.5))
  // How many atoms are in flight and how many glints pop around them. The
  // density knob scales both; 0 turns the stream off without touching the glow.
  property real sparkDensity: 1
  property bool sparkle: true
  // A cell parked full brims: the halo swells harder and the glints keep
  // popping, slower, because the energy is in there even when nothing moves.
  // Atoms stay tied to flow — a full cell on the wall has no current to show.
  property bool hum: true
  readonly property real density: Math.max(0, Math.min(3, Number(sparkDensity) || 0))
  readonly property int pipCount: Math.round((hero ? 14 : 8) * density)
  readonly property int twinkleCount: sparkle ? Math.round((hero ? 12 : 6) * density) : 0
  readonly property real twinkleSize: hero ? Style.space(9) : Style.space(5)
  readonly property real twinkleOvershoot: hero ? Style.space(6) : Style.space(2)
  readonly property real cornerRadius: hero ? Style.space(7) : Style.space(3)

  implicitWidth: laneWidth + cellWidth + nubWidth
  implicitHeight: cellHeight

  readonly property bool flowingIn: mode === "in"
  readonly property bool flowingOut: mode === "out"
  readonly property bool flowing: flowingIn || flowingOut
  readonly property bool onAc: mode === "in" || mode === "hold" || mode === "full"
  // The level colour: where the charge sits between the three stops, walked
  // round the hue wheel so blue → yellow passes through green, not grey.
  readonly property var levelStops: Model.levelBlend(fraction, lowFraction)
  function stopColor(name) {
    return name === "full" ? fullColor : (name === "mid" ? midColor : lowColor)
  }
  readonly property color levelColor: {
    var m = Model.mixRgb(stopColor(levelStops.from), stopColor(levelStops.to), levelStops.t)
    return Qt.rgba(m.r, m.g, m.b, 1)
  }

  // What the things around the cell wear: the level colour while power is
  // moving or the cell is full, muted while it is parked at a threshold.
  readonly property string flowRole: Model.flowRole(mode)
  readonly property color flowColor: flowRole === "level" ? levelColor
    : flowRole === "muted" ? muted
    : foreground

  // How hard the halo can glow in each state. Charging and draining are the
  // full show — the glow is the point — a low cell throbs, and a parked or
  // full cell simmers.
  readonly property bool humming: hum && mode === "full"
  readonly property real glowPeak: !glow ? 0
    : flowingIn ? 1.0
    : flowingOut ? (low ? 1.0 : 0.9)
    : mode === "full" ? (hum ? 0.9 : 0.6)
    : mode === "hold" ? 0.35
    : 0
  // Glints are near-white flashes of whatever the atoms are made of.
  readonly property color glintColor: flowingIn ? Qt.lighter(accent, 1.5) : Qt.lighter(levelColor, 1.5)
  readonly property int breathPeriod: low && flowingOut ? 900 : (flowingIn ? 1500 : (humming ? 2200 : 3000))
  // Glints rest longer on a humming cell: a crackle, not a shower.
  readonly property real glintRestScale: humming ? 2.5 : 1
  readonly property int pipPeriod: Model.pipPeriod(watts, hero ? 2200 : 1500)

  readonly property real cellX: laneWidth
  readonly property real cellY: (height - cellHeight) / 2
  readonly property real innerX: cellX + inset
  readonly property real innerW: Math.max(0, cellWidth - inset * 2)
  readonly property real fillWidth: Math.max(0, innerW * Math.max(0, Math.min(1, fraction)))
  readonly property real fillEdgeX: innerX + fillWidth

  // The breath: 0.45..1, multiplied into the halo's opacity. The floor stays
  // high enough that the cell never stops glowing, it only swells.
  property real haloLevel: 0.75
  SequentialAnimation on haloLevel {
    running: root.animate && root.glowPeak > 0
    loops: Animation.Infinite
    alwaysRunToEnd: true
    NumberAnimation { from: 0.45; to: 1.0; duration: root.breathPeriod / 2; easing.type: Easing.InOutSine }
    NumberAnimation { from: 1.0; to: 0.45; duration: root.breathPeriod / 2; easing.type: Easing.InOutSine }
  }

  // ---- The far end of the wire --------------------------------------------
  // On AC the lane holds a bolt (bar) or a plug (hero), lit in the flow
  // colour. On battery the hero shows the laptop it is feeding; the bar
  // leaves the lane empty so the exiting sparks have somewhere to go.
  Text {
    id: laneGlyph
    readonly property string key: Model.laneKey(root.mode)
    visible: key !== "" && (root.hero || root.onAc)
    textFormat: Text.PlainText
    text: Glyphs.glyph(key === "plug" && !root.hero ? "bolt" : key)
    x: (root.laneWidth - width) / 2 - (root.hero ? Style.space(3) : 0)
    anchors.verticalCenter: parent.verticalCenter
    // The bolt / plug is the wall's energy: accent. Parked, it dims to muted.
    // The laptop on battery wears the cell's level colour.
    color: !root.onAc ? root.levelColor : (root.mode === "hold" ? root.muted : root.accent)
    font.family: root.fontFamily
    font.pixelSize: root.hero ? Style.font.display : Style.font.bodySmall
    renderType: Text.NativeRendering

    Behavior on color { ColorAnimation { duration: 220 } }
  }

  // ---- The cell: a hidden stencil the halo draws --------------------------
  Item {
    id: cellArt
    visible: false
    x: root.cellX
    y: root.cellY
    width: root.cellWidth + root.nubWidth
    height: root.cellHeight

    Rectangle {
      id: body
      x: 0
      y: 0
      width: root.cellWidth
      height: root.cellHeight
      radius: root.cornerRadius
      color: Util.alpha(root.levelColor, 0.12)
      border.width: root.strokeWidth
      border.color: Util.alpha(root.levelColor, 0.95)

      Behavior on color { ColorAnimation { duration: 260 } }
      Behavior on border.color { ColorAnimation { duration: 260 } }
    }

    Rectangle {
      id: nub
      x: root.cellWidth
      y: Math.round((root.cellHeight - root.nubHeight) / 2)
      width: root.nubWidth
      height: root.nubHeight
      radius: Math.min(2, root.nubWidth / 2)
      color: Util.alpha(root.levelColor, 0.95)

      Behavior on color { ColorAnimation { duration: 260 } }
    }

    Rectangle {
      id: fill
      x: root.inset
      y: root.inset
      width: root.fillWidth
      height: root.cellHeight - root.inset * 2
      radius: Math.max(1, root.cornerRadius - root.inset)
      color: root.levelColor

      Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: 260 } }
    }
  }

  MultiEffect {
    id: halo
    source: cellArt
    anchors.fill: cellArt
    autoPaddingEnabled: true
    shadowEnabled: root.glowPeak > 0
    shadowColor: root.levelColor
    shadowBlur: 1.0
    blurMax: root.hero ? 56 : 40
    shadowScale: root.hero ? 1.12 : 1.5
    shadowHorizontalOffset: 0
    shadowVerticalOffset: 0
    shadowOpacity: root.glowPeak * root.haloLevel

    Behavior on shadowColor { ColorAnimation { duration: 260 } }
  }

  // ---- Charging shimmer: a highlight sweeping along the fill --------------
  Rectangle {
    id: shimmer
    readonly property real span: root.hero ? Style.space(18) : Style.space(6)
    visible: root.animate && root.flowingIn && root.fillWidth > span * 1.5
    y: root.cellY + root.inset
    height: root.cellHeight - root.inset * 2
    width: span
    radius: fill.radius
    opacity: 0
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: "transparent" }
      GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.55) }
      GradientStop { position: 1.0; color: "transparent" }
    }

    SequentialAnimation {
      running: shimmer.visible
      loops: Animation.Infinite
      ParallelAnimation {
        NumberAnimation {
          target: shimmer; property: "x"
          from: root.innerX; to: root.fillEdgeX - shimmer.span
          duration: root.pipPeriod * 1.6
          easing.type: Easing.InOutQuad
        }
        SequentialAnimation {
          NumberAnimation { target: shimmer; property: "opacity"; from: 0; to: 0.9; duration: root.pipPeriod * 0.4 }
          NumberAnimation { target: shimmer; property: "opacity"; to: 0; duration: root.pipPeriod * 1.2 }
        }
      }
      PauseAnimation { duration: 500 }
    }
  }

  // ---- Edge flare: the fill's leading edge pulses while it advances -------
  Rectangle {
    visible: root.flowingIn && root.fillWidth > 2
    x: root.fillEdgeX - width
    y: root.cellY + root.inset
    width: Math.max(1.5, root.strokeWidth)
    height: root.cellHeight - root.inset * 2
    color: Qt.lighter(root.levelColor, 1.6)
    opacity: 0.6

    SequentialAnimation on opacity {
      running: root.animate && root.flowingIn
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { from: 0.25; to: 1.0; duration: 500; easing.type: Easing.InOutSine }
      NumberAnimation { from: 1.0; to: 0.25; duration: 500; easing.type: Easing.InOutSine }
    }
  }

  // ---- Hold marker: a lock over a parked cell (hero only) -----------------
  Text {
    visible: root.hero && root.mode === "hold"
    textFormat: Text.PlainText
    text: Glyphs.glyph("lock")
    x: root.cellX + root.cellWidth / 2 - width / 2
    anchors.verticalCenter: parent.verticalCenter
    color: root.foreground
    opacity: 0.75
    font.family: root.fontFamily
    font.pixelSize: Style.font.heading
    renderType: Text.NativeRendering
  }

  // ---- The number inside the cell (bar) -----------------------------------
  // The charge as digits over the fill. No "%": a number inside a battery is
  // a percentage already, and no outline: it read as a box round the number.
  // Legibility comes from two clipped copies instead. Over the fill the
  // digits wear whichever of foreground / bar background stands out more from
  // the level colour; past the fill's edge they are plain foreground on the
  // bar. The seam is the fill's own animated edge, so the colour swap rides
  // with it. Drawn before the atoms and glints so the stream passes over it.
  readonly property string labelText: String(Math.round(Math.max(0, Math.min(1, fraction)) * 100))
  readonly property int labelFontPx: Math.max(8, Math.round(cellHeight * 0.72))
  readonly property real labelX: cellX + Math.round((cellWidth - labelMetrics.width) / 2)
  readonly property color labelOnFill: {
    var lvl = { r: levelColor.r, g: levelColor.g, b: levelColor.b }
    var fg = { r: foreground.r, g: foreground.g, b: foreground.b }
    var bg = { r: background.r, g: background.g, b: background.b }
    return Model.contrastRatio(lvl, bg) > Model.contrastRatio(lvl, fg) ? background : foreground
  }

  Text {
    id: labelMetrics
    visible: false
    textFormat: Text.PlainText
    text: root.labelText
    font.family: root.fontFamily
    font.pixelSize: root.labelFontPx
    font.bold: true
  }

  component CellLabel: Text {
    textFormat: Text.PlainText
    text: root.labelText
    anchors.verticalCenter: parent.verticalCenter
    font.family: root.fontFamily
    font.pixelSize: root.labelFontPx
    font.bold: true

    Behavior on color { ColorAnimation { duration: 220 } }
  }

  Item {
    id: labelOverFill
    visible: root.labelled && width > 0
    clip: true
    x: root.innerX
    y: 0
    width: fill.width
    height: root.height

    CellLabel { x: root.labelX - labelOverFill.x; color: root.labelOnFill }
  }

  Item {
    id: labelPastFill
    visible: root.labelled && width > 0
    clip: true
    x: root.innerX + fill.width
    y: 0
    width: Math.max(0, root.cellX + root.cellWidth - x)
    height: root.height

    CellLabel { x: root.labelX - labelPastFill.x; color: root.foreground }
  }

  // ---- Atoms riding in ----------------------------------------------------
  // A stream, not a convoy: every atom has its own size, band, speed, delay
  // and rest (Model.sparkSpec — deterministic per index, so nothing changes
  // under you). Born in the lane, they cross into the cell and die at the
  // fill's leading edge, rising as they go. Each is a white-hot core inside
  // a soft halo, which reads as a glowing particle without a shader.
  Repeater {
    model: root.pipCount

    Item {
      id: atomIn
      required property int index
      readonly property var spec: Model.sparkSpec(index, root.pipCount)
      readonly property real size: root.pipSize * spec.size
      visible: root.animate && root.flowingIn
      width: size
      height: size
      opacity: 0

      Rectangle {
        anchors.centerIn: parent
        width: parent.width * 2.6
        height: width
        radius: width / 2
        color: root.accent
        opacity: 0.32
      }
      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Qt.lighter(root.accent, 1.35)
      }
      Rectangle {
        anchors.centerIn: parent
        width: Math.max(1, parent.width * 0.45)
        height: width
        radius: width / 2
        color: "white"
        opacity: 0.9
      }

      SequentialAnimation {
        running: atomIn.visible
        loops: Animation.Infinite
        PauseAnimation { duration: atomIn.spec.delay * root.pipPeriod }
        ParallelAnimation {
          NumberAnimation {
            target: atomIn; property: "x"
            from: root.laneWidth * 0.12 - atomIn.size / 2
            to: Math.max(root.innerX, root.fillEdgeX - atomIn.size)
            duration: root.pipPeriod * atomIn.spec.speed
            easing.type: Easing.InQuad
          }
          NumberAnimation {
            target: atomIn; property: "y"
            from: root.cellY + root.cellHeight * atomIn.spec.yFrom - atomIn.size / 2
            to: root.cellY + root.cellHeight * atomIn.spec.yTo - atomIn.size / 2
            duration: root.pipPeriod * atomIn.spec.speed
          }
          SequentialAnimation {
            NumberAnimation { target: atomIn; property: "opacity"; from: 0; to: atomIn.spec.peak; duration: root.pipPeriod * atomIn.spec.speed * 0.25 }
            PauseAnimation { duration: root.pipPeriod * atomIn.spec.speed * 0.45 }
            NumberAnimation { target: atomIn; property: "opacity"; to: 0; duration: root.pipPeriod * atomIn.spec.speed * 0.3 }
          }
        }
        PauseAnimation { duration: atomIn.spec.rest * root.pipPeriod }
      }
    }
  }

  // ---- Atoms riding out ---------------------------------------------------
  // Born at the fill's edge, they run back through the cell and out of the
  // lane, sinking and fading: energy leaving. Same stream rules, mirrored,
  // and they wear the cell's level colour because they are the cell's charge.
  Repeater {
    model: root.pipCount

    Item {
      id: atomOut
      required property int index
      readonly property var spec: Model.sparkSpec(index, root.pipCount)
      readonly property real size: root.pipSize * spec.size
      visible: root.animate && root.flowingOut
      width: size
      height: size
      opacity: 0

      Rectangle {
        anchors.centerIn: parent
        width: parent.width * 2.6
        height: width
        radius: width / 2
        color: root.levelColor
        opacity: 0.32
      }
      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Qt.lighter(root.levelColor, 1.25)
      }
      Rectangle {
        anchors.centerIn: parent
        width: Math.max(1, parent.width * 0.45)
        height: width
        radius: width / 2
        color: "white"
        opacity: 0.9
      }

      SequentialAnimation {
        running: atomOut.visible
        loops: Animation.Infinite
        PauseAnimation { duration: atomOut.spec.delay * root.pipPeriod }
        ParallelAnimation {
          NumberAnimation {
            target: atomOut; property: "x"
            from: Math.max(root.innerX, root.fillEdgeX - atomOut.size)
            to: root.laneWidth * 0.05 - atomOut.size / 2
            duration: root.pipPeriod * atomOut.spec.speed
            easing.type: Easing.OutQuad
          }
          NumberAnimation {
            target: atomOut; property: "y"
            from: root.cellY + root.cellHeight * atomOut.spec.yTo - atomOut.size / 2
            to: root.cellY + root.cellHeight * atomOut.spec.yFrom - atomOut.size / 2
            duration: root.pipPeriod * atomOut.spec.speed
          }
          SequentialAnimation {
            NumberAnimation { target: atomOut; property: "opacity"; from: 0; to: atomOut.spec.peak; duration: root.pipPeriod * atomOut.spec.speed * 0.2 }
            PauseAnimation { duration: root.pipPeriod * atomOut.spec.speed * 0.4 }
            NumberAnimation { target: atomOut; property: "opacity"; to: 0; duration: root.pipPeriod * atomOut.spec.speed * 0.4 }
          }
        }
        PauseAnimation { duration: atomOut.spec.rest * root.pipPeriod }
      }
    }
  }

  // ---- Glints ---------------------------------------------------------------
  // Four-point sparkles that pop and spin wherever the atoms are landing or
  // leaving: across the lane and the cell up to the fill's edge, a little
  // outside the outline too, like sparks flying off. Positions and timings
  // are deterministic (Model.twinkleSpec); the motion is all scale / opacity
  // / rotation, so it costs the compositor nothing to rasterise.
  Repeater {
    model: root.twinkleCount

    Item {
      id: glint
      required property int index
      readonly property var spec: Model.twinkleSpec(index, root.twinkleCount)
      readonly property real size: root.twinkleSize * spec.size
      visible: root.animate && (root.flowing || root.humming)
      width: size
      height: size
      x: root.laneWidth * 0.1 + spec.x * Math.max(0, root.fillEdgeX - root.laneWidth * 0.1) - size / 2
      y: root.cellY - root.twinkleOvershoot + spec.y * (root.cellHeight + root.twinkleOvershoot * 2) - size / 2
      scale: 0
      opacity: 0

      Rectangle {
        anchors.centerIn: parent
        width: Math.max(1, parent.width * 0.18)
        height: parent.height
        radius: width / 2
        color: root.glintColor
      }
      Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: Math.max(1, parent.height * 0.18)
        radius: height / 2
        color: root.glintColor
      }
      Rectangle {
        anchors.centerIn: parent
        width: Math.max(1, parent.width * 0.4)
        height: width
        radius: width / 2
        color: "white"
        opacity: 0.95
      }

      SequentialAnimation {
        running: glint.visible
        loops: Animation.Infinite
        PauseAnimation { duration: glint.spec.delay * 1000 }
        ParallelAnimation {
          SequentialAnimation {
            NumberAnimation { target: glint; property: "scale"; from: 0; to: 1; duration: 220; easing.type: Easing.OutBack }
            NumberAnimation { target: glint; property: "scale"; to: 0; duration: 380; easing.type: Easing.InQuad }
          }
          SequentialAnimation {
            NumberAnimation { target: glint; property: "opacity"; from: 0; to: 1; duration: 180 }
            NumberAnimation { target: glint; property: "opacity"; to: 0; duration: 420 }
          }
          NumberAnimation { target: glint; property: "rotation"; from: 0; to: glint.spec.spin; duration: 600 }
        }
        PauseAnimation { duration: glint.spec.rest * 1000 * root.glintRestScale }
      }
    }
  }
}
