import QtQuick
import QtQuick.Effects
import qs.Commons
import "Model.js" as Model
import "Glyphs.js" as Glyphs

// The flux cell. A battery drawn from plain rectangles, wrapped in a GPU glow
// the colour of whatever the power is doing, with sparks that ride INTO the
// cell while it charges (rising) and OUT of it while it drains (sinking).
//
// One component, two scales: `hero: false` is the bar version beside the
// percentage, `hero: true` is the panel version with a wider lane.
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

  property real cellWidth: hero ? Style.space(100) : Style.space(24)
  property real cellHeight: hero ? Style.space(38) : Style.space(11)
  property real laneWidth: hero ? Style.space(30) : Style.space(13)

  readonly property real nubWidth: hero ? Style.space(4) : Math.max(2, Style.spaceReal(2))
  readonly property real nubHeight: Math.round(cellHeight * 0.45)
  readonly property real strokeWidth: hero ? Math.max(2, Style.spaceReal(2)) : Math.max(1, Style.spaceReal(1.25))
  readonly property real inset: strokeWidth + (hero ? Style.space(3) : Math.max(1, Style.spaceReal(1.5)))
  readonly property real pipSize: hero ? Style.space(5) : Math.max(3, Style.spaceReal(2.5))
  readonly property int pipCount: hero ? 4 : 3
  readonly property real cornerRadius: hero ? Style.space(7) : Style.space(3)

  implicitWidth: laneWidth + cellWidth + nubWidth
  implicitHeight: cellHeight

  readonly property bool flowingIn: mode === "in"
  readonly property bool flowingOut: mode === "out"
  readonly property bool flowing: flowingIn || flowingOut
  readonly property bool onAc: mode === "in" || mode === "hold" || mode === "full"
  readonly property string flowRole: Model.flowRole(mode, low)
  readonly property color flowColor: flowRole === "accent" ? accent
    : flowRole === "urgent" ? urgent
    : flowRole === "muted" ? muted
    : foreground

  // How hard the halo can glow in each state. Charging is the full show; a
  // low cell on battery is too, in red; a parked or full cell just simmers.
  readonly property real glowPeak: !glow ? 0
    : flowingIn ? 1.0
    : flowingOut ? (low ? 1.0 : 0.6)
    : mode === "full" ? 0.5
    : mode === "hold" ? 0.3
    : 0
  readonly property int breathPeriod: low && flowingOut ? 900 : (flowingIn ? 1500 : 3000)
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
    color: root.onAc || root.low ? root.flowColor : Util.alpha(root.foreground, 0.6)
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
      color: Util.alpha(root.foreground, 0.06)
      border.width: root.strokeWidth
      border.color: Util.alpha(root.foreground, 0.9)
    }

    Rectangle {
      id: nub
      x: root.cellWidth
      y: Math.round((root.cellHeight - root.nubHeight) / 2)
      width: root.nubWidth
      height: root.nubHeight
      radius: Math.min(2, root.nubWidth / 2)
      color: Util.alpha(root.foreground, 0.9)
    }

    Rectangle {
      id: fill
      x: root.inset
      y: root.inset
      width: root.fillWidth
      height: root.cellHeight - root.inset * 2
      radius: Math.max(1, root.cornerRadius - root.inset)
      color: root.flowColor

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
    shadowColor: root.flowColor
    shadowBlur: 1.0
    blurMax: root.hero ? 48 : 24
    shadowScale: root.hero ? 1.08 : 1.24
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
    color: Qt.lighter(root.flowColor, 1.6)
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

  // ---- Sparks riding in ---------------------------------------------------
  // Born in the lane, they cross into the cell and die at the fill's leading
  // edge, rising as they go. Staggered by a fraction of the period so they
  // read as a current rather than a convoy.
  Repeater {
    model: root.pipCount

    Rectangle {
      id: pipIn
      required property int index
      visible: root.animate && root.flowingIn
      width: root.pipSize
      height: root.pipSize
      radius: root.pipSize / 2
      color: Qt.lighter(root.flowColor, 1.25)
      opacity: 0

      SequentialAnimation {
        running: pipIn.visible
        loops: Animation.Infinite
        PauseAnimation { duration: pipIn.index * root.pipPeriod / root.pipCount }
        ParallelAnimation {
          NumberAnimation {
            target: pipIn; property: "x"
            from: root.laneWidth * 0.12
            to: Math.max(root.innerX, root.fillEdgeX - root.pipSize)
            duration: root.pipPeriod
            easing.type: Easing.InQuad
          }
          NumberAnimation {
            target: pipIn; property: "y"
            from: root.cellY + root.cellHeight * 0.72 - root.pipSize / 2
            to: root.cellY + root.cellHeight * 0.28 - root.pipSize / 2
            duration: root.pipPeriod
          }
          SequentialAnimation {
            NumberAnimation { target: pipIn; property: "opacity"; from: 0; to: 0.95; duration: root.pipPeriod * 0.25 }
            PauseAnimation { duration: root.pipPeriod * 0.45 }
            NumberAnimation { target: pipIn; property: "opacity"; to: 0; duration: root.pipPeriod * 0.3 }
          }
        }
      }
    }
  }

  // ---- Sparks riding out --------------------------------------------------
  // Born at the fill's edge, they run back through the cell and out of the
  // lane, sinking and fading: energy leaving.
  Repeater {
    model: root.pipCount

    Rectangle {
      id: pipOut
      required property int index
      visible: root.animate && root.flowingOut
      width: root.pipSize
      height: root.pipSize
      radius: root.pipSize / 2
      color: Qt.lighter(root.flowColor, 1.15)
      opacity: 0

      SequentialAnimation {
        running: pipOut.visible
        loops: Animation.Infinite
        PauseAnimation { duration: pipOut.index * root.pipPeriod / root.pipCount }
        ParallelAnimation {
          NumberAnimation {
            target: pipOut; property: "x"
            from: Math.max(root.innerX, root.fillEdgeX - root.pipSize)
            to: root.laneWidth * 0.05
            duration: root.pipPeriod
            easing.type: Easing.OutQuad
          }
          NumberAnimation {
            target: pipOut; property: "y"
            from: root.cellY + root.cellHeight * 0.28 - root.pipSize / 2
            to: root.cellY + root.cellHeight * 0.72 - root.pipSize / 2
            duration: root.pipPeriod
          }
          SequentialAnimation {
            NumberAnimation { target: pipOut; property: "opacity"; from: 0; to: 0.95; duration: root.pipPeriod * 0.2 }
            PauseAnimation { duration: root.pipPeriod * 0.4 }
            NumberAnimation { target: pipOut; property: "opacity"; to: 0; duration: root.pipPeriod * 0.4 }
          }
        }
      }
    }
  }
}
