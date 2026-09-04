import QtQuick
import qs.Commons

// The last hour of power as bars off a centre line: up is power going in,
// down is power going out, flat is parked. Newest at the right edge.
//
// Repaints ONLY when a sample lands (every 30 s) or the scale changes, never
// per frame. The one moving part, the ring that swells off the newest bar
// while power flows, is a scene-graph scale/opacity animation on a plain
// Rectangle, so it costs no rasterisation.
Item {
  id: root

  property var samples: []          // signed watts, oldest first — + in, − out
  property int capacity: 120        // how many samples span the full width
  property real fullScale: 10       // what the top and bottom edges mean
  property bool live: false         // power is moving: pulse the head
  property bool animate: true
  property bool low: false
  property color accent: Color.accent
  property color foreground: Color.popups.text
  property color urgent: Color.urgent
  property color muted: Color.muted

  implicitHeight: Style.space(44)

  readonly property int count: Array.isArray(samples) ? samples.length : 0
  readonly property real inset: Style.space(2)
  readonly property real midY: height / 2
  readonly property real halfH: Math.max(1, height / 2 - inset)
  readonly property real slot: (width - inset * 2) / Math.max(1, capacity)
  readonly property real barW: Math.max(1, slot - 1)

  // Where a sample sits. Newest is pinned to the right edge and the spacing
  // is fixed by `capacity`, so a young trace grows in from the right rather
  // than stretching to fill — spacing IS the time axis.
  function xAt(index) {
    return width - inset - (count - index) * slot
  }

  function hAt(value) {
    var frac = Math.min(1, Math.abs(Number(value) || 0) / Math.max(0.001, fullScale))
    return Math.max(1, frac * halfH)
  }

  readonly property real headValue: count > 0 ? Number(samples[count - 1]) || 0 : 0
  readonly property real headX: count > 0 ? xAt(count - 1) + barW / 2 : width - inset
  readonly property real headY: count > 0
    ? (headValue > 0 ? midY - hAt(headValue) : (headValue < 0 ? midY + hAt(headValue) : midY))
    : midY
  readonly property color headColor: headValue > 0 ? accent : (headValue < 0 ? (low ? urgent : foreground) : muted)

  Canvas {
    id: trace
    anchors.fill: parent
    renderTarget: Canvas.Image
    renderStrategy: Canvas.Cooperative

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width, h = height
      if (w <= 0 || h <= 0) return

      // The centre line: what "parked" is flat against.
      ctx.strokeStyle = Util.alpha(root.foreground, 0.18).toString()
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(root.inset, root.midY + 0.5)
      ctx.lineTo(w - root.inset, root.midY + 0.5)
      ctx.stroke()

      var n = root.count
      for (var i = 0; i < n; i++) {
        var v = Number(root.samples[i]) || 0
        var x = root.xAt(i)
        var age = n > 1 ? i / (n - 1) : 1          // 0 oldest .. 1 newest
        var alpha = 0.35 + 0.6 * age
        if (v > 0) {
          ctx.fillStyle = Util.alpha(root.accent, alpha).toString()
          var hu = root.hAt(v)
          ctx.fillRect(x, root.midY - hu, root.barW, hu)
        } else if (v < 0) {
          ctx.fillStyle = Util.alpha(root.foreground, alpha * 0.85).toString()
          var hd = root.hAt(v)
          ctx.fillRect(x, root.midY, root.barW, hd)
        } else {
          ctx.fillStyle = Util.alpha(root.muted, alpha).toString()
          ctx.fillRect(x, root.midY - 1, root.barW, 2)
        }
      }
    }
  }

  // Data-driven repaints only.
  onSamplesChanged: trace.requestPaint()
  onFullScaleChanged: trace.requestPaint()
  onCapacityChanged: trace.requestPaint()
  onAccentChanged: trace.requestPaint()
  onForegroundChanged: trace.requestPaint()
  onMutedChanged: trace.requestPaint()

  // ---- The head -------------------------------------------------------------
  // A dot on the tip of the newest bar, and while power moves a ring that
  // swells out of it: the trace's way of saying "still going" between samples.
  Rectangle {
    id: head
    visible: root.count > 0
    width: Math.max(3, Style.space(4))
    height: width
    radius: width / 2
    x: root.headX - width / 2
    y: root.headY - height / 2
    color: root.headColor

    Rectangle {
      visible: root.live
      anchors.centerIn: parent
      width: parent.width * 2.8
      height: width
      radius: width / 2
      color: "transparent"
      border.width: 1
      border.color: root.headColor
      opacity: 0

      SequentialAnimation on scale {
        running: root.animate && root.live && head.visible
        loops: Animation.Infinite
        NumberAnimation { from: 0.5; to: 1.4; duration: 1400; easing.type: Easing.OutCubic }
        NumberAnimation { from: 1.4; to: 0.5; duration: 0 }
      }
      SequentialAnimation on opacity {
        running: root.animate && root.live && head.visible
        loops: Animation.Infinite
        NumberAnimation { from: 0.85; to: 0.0; duration: 1400; easing.type: Easing.OutCubic }
        NumberAnimation { from: 0.0; to: 0.85; duration: 0 }
      }
    }
  }
}
