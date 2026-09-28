import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons
import "Model.js" as Model

// VinylPod popout. The bar widget hosts this component and KeyboardPanel
// provides the actual anchored popup window. This follows the same
// anchorItem/owner/bar pattern used by Omarchy bar-widget panels.
Item {
  id: root

  property var anchorItem: null
  property var hostWidget: null
  property var bar: null
  readonly property var barIdentity: hostWidget || root
  property bool opened: false
  readonly property bool popoutSwitchClosing: false
  readonly property bool showWhenClosed: false

  function open() { root.opened = true }
  function close() { root.opened = false }
  function toggle() { root.opened = !root.opened }
  function closeForPopoutSwitch() { root.close() }

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: Model.findSpotify(players)
  readonly property bool live: player !== null && player !== undefined
  readonly property bool playing: live && player.isPlaying === true
  readonly property string trackTitle: live ? String(player.trackTitle || "") : ""
  readonly property string trackArtist: live ? String(player.trackArtist || "") : ""
  readonly property string artUrl: live ? String(player.trackArtUrl || "") : ""
  readonly property real trackLength: live && player.lengthSupported ? Math.max(0, player.length) : 0
  // MPRIS position is not guaranteed to emit a signal every frame. Keep a
  // local playback clock between MPRIS position updates so the progress bar
  // follows playback smoothly. The raw MPRIS position is still sampled often
  // enough to catch seeks, pauses, track changes, and player-side corrections.
  property real playbackPosition: 0
  property real positionAnchor: 0
  property double positionAnchorMs: 0
  property real lastPlayerPosition: 0
  property string positionTrackKey: ""
  readonly property real trackPosition: trackLength > 0
    ? Math.max(0, Math.min(trackLength, playbackPosition))
    : Math.max(0, playbackPosition)
  readonly property real progress: trackLength > 0
    ? Math.max(0, Math.min(1, trackPosition / trackLength))
    : 0

  function playerTrackKey() {
    if (!live) return ""
    return String(player.trackId || player.trackTitle || "") + "|" + String(player.length || 0)
  }

  function syncPlaybackPosition(force) {
    if (!live || !player.positionSupported) {
      playbackPosition = 0
      positionAnchor = 0
      positionAnchorMs = 0
      positionTrackKey = ""
      return
    }

    var raw = Math.max(0, Number(player.position) || 0)
    var key = playerTrackKey()
    var now = Date.now()
    var trackChanged = key !== positionTrackKey
    var expected = positionAnchor
    if (playing && positionAnchorMs > 0)
      expected += Math.max(0, (now - positionAnchorMs) / 1000)

    // MPRIS position can lag behind our local clock. Treat a sizeable
    // difference as a seek/player correction; otherwise keep the smooth clock.
    var seeked = !playing || force || trackChanged || positionAnchorMs === 0
      || Math.abs(raw - expected) > 1.0

    if (seeked) {
      positionAnchor = raw
      positionAnchorMs = now
      playbackPosition = raw
    } else {
      playbackPosition = expected
    }

    lastPlayerPosition = raw
    positionTrackKey = key
  }

  Timer {
    id: playbackClock
    interval: 100
    repeat: true
    running: root.live
    triggeredOnStart: true
    onTriggered: root.syncPlaybackPosition(false)
  }

  onPlayingChanged: syncPlaybackPosition(true)
  onTrackTitleChanged: syncPlaybackPosition(true)
  onTrackLengthChanged: syncPlaybackPosition(true)
  onLiveChanged: syncPlaybackPosition(true)

  // ------------------------------------------------- look & motion knobs
  property real panelOpacity: 0.6      // translucent panel background
  property real screenOpacity: 0.85    // black iPod screen (kept close to black)
  property real wheelDrop: 30          // extra gap between screen and wheel
  property real rpm: 33.333

  // Motion model ported from omarchy-vinyl (ui.rs tick): a heavy platter that
  // spins up fast and coasts down slowly, and a tone arm that only drops once
  // the platter is up to speed, rides inward with progress, and lifts on pause.
  property real vinylAngle: 0          // degrees
  property real angVel: 0              // degrees / second
  readonly property real restAngle: 77 // arm parked, needle off the record
  readonly property real needleAngle: 135 - (43 - 18 * progress)
  readonly property bool platterUp: playing && angVel > rpm * 3
  readonly property real armTarget: platterUp ? needleAngle : restAngle
  property real armAngle: 77
  // 0 = needle on the groove, 1 = fully lifted (drives the shadow offset)
  readonly property real armLift: Math.max(0, Math.min(1, Math.abs(armAngle - needleAngle) / 8))

  function stepMotion(dt) {
    dt = Math.min(dt, 0.1)
    var spinTarget = playing ? rpm * 6 : 0
    var k = spinTarget > angVel ? 3.0 : 1.4
    angVel += (spinTarget - angVel) * (1 - Math.exp(-k * dt))
    if (spinTarget === 0 && Math.abs(angVel) < 0.5) angVel = 0
    vinylAngle = (vinylAngle + angVel * dt) % 360

    armAngle += (armTarget - armAngle) * (1 - Math.exp(-4.5 * dt))
    if (Math.abs(armTarget - armAngle) < 0.02) armAngle = armTarget
  }

  FrameAnimation {
    running: root.opened && (root.playing || root.angVel !== 0
                             || Math.abs(root.armTarget - root.armAngle) > 0.02)
    onTriggered: root.stepMotion(frameTime)
  }

  // ---------------------------------------------------- album-art probe
  // Unchanged from Spotmarchy's Panel.qml: Qt can display the cover but not
  // tell us its colour, so an ImageMagick probe (via Model.js) reads a
  // downloaded copy and hands back a dominant colour plus a local file to
  // display from — the panel never points an Image straight at the raw
  // artUrl.
  property string artDominant: ""
  property string artFile: ""
  property string artProbed: ""
  readonly property string artSourceUrl: Model.fileUrl(artFile)

  onArtUrlChanged: artProbeDelay.restart()
  Component.onCompleted: probeArt()

  function probeArt() {
    var target = Model.artProbeTarget(root.artUrl)
    if (!target) {
      root.artFile = ""
      root.artDominant = ""
      root.artProbed = ""
      return
    }
    if (root.artProbed === root.artUrl) return
    if (artProbe.running) artProbe.running = false
    artProbe.pending = root.artUrl
    artProbe.command = ["/bin/sh", "-c", Model.artProbeScript(), "sh", target]
    artProbe.running = true
  }

  Timer {
    id: artProbeDelay
    interval: 250
    onTriggered: root.probeArt()
  }

  Process {
    id: artProbe
    property string pending: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (artProbe.pending !== root.artUrl) return
        var probe = Model.parseArtProbe(text)
        if (!probe) return
        root.artFile = probe.file
        root.artDominant = probe.dominant
        root.artProbed = artProbe.pending
      }
    }
  }

  // ----------------------------------------------------------------- actions
  function playPause() {
    if (!live) return false
    if (player.canTogglePlaying) { player.togglePlaying(); return true }
    if (playing && player.canPause) { player.pause(); return true }
    if (!playing && player.canPlay) { player.play(); return true }
    return false
  }
  function skipNext() {
    if (!live || !player.canGoNext) return false
    player.next()
    return true
  }
  function skipPrevious() {
    if (!live || !player.canGoPrevious) return false
    player.previous()
    return true
  }

  // Circular cover art. `clip: true` never follows a Rectangle's radius in
  // QML, so the image is masked through a circle instead.
  component CircleArt: Item {
    id: circ
    property string source: ""
    property color fill: Color.accent
    property real inset: 0

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: circ.fill
    }

    Image {
      id: artImg
      anchors.fill: parent
      anchors.margins: circ.inset
      visible: circ.source !== ""
      source: circ.source
      fillMode: Image.PreserveAspectCrop
      layer.enabled: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: artMask
      }
    }

    Item {
      id: artMask
      anchors.fill: artImg
      visible: false
      layer.enabled: true
      Rectangle { anchors.fill: parent; radius: width / 2 }
    }
  }

  // Clips its children to a circle (used for the arm's shadow, which only
  // falls on the record).
  component CircleClip: Item {
    default property alias content: holder.data
    layer.enabled: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: clipMask
    }
    Item { id: holder; anchors.fill: parent }
    Item {
      id: clipMask
      anchors.fill: parent
      visible: false
      layer.enabled: true
      Rectangle { anchors.fill: parent; radius: width / 2 }
    }
  }

  // The tone arm along +x from its origin: counterweight, tube, headshell,
  // stylus. In shadowMode every part is one flat translucent ink instead.
  component ArmBody: Item {
    id: ab
    property real u: 1
    property real len: 105
    property bool shadowMode: false
    property color ink: "#26000000"
    width: 0
    height: 0

    Rectangle {
      x: -18 * ab.u; y: -5 * ab.u
      width: 12 * ab.u; height: 10 * ab.u; radius: 2 * ab.u
      color: ab.shadowMode ? ab.ink : "#5a5a5a"
    }
    Rectangle {
      x: -8 * ab.u; y: -1.5 * ab.u
      width: ab.len - 6 * ab.u; height: 3 * ab.u; radius: height / 2
      gradient: Gradient {
        GradientStop { position: 0.0; color: ab.shadowMode ? ab.ink : "#e6e6e6" }
        GradientStop { position: 1.0; color: ab.shadowMode ? ab.ink : "#9a9a9a" }
      }
    }
    Rectangle {
      x: ab.len - 14 * ab.u; y: -3.5 * ab.u
      width: 14 * ab.u; height: 7 * ab.u; radius: 1.5 * ab.u
      color: ab.shadowMode ? ab.ink : "#1c1c1c"
      border.width: ab.shadowMode ? 0 : 1
      border.color: "#555555"
    }
    Rectangle {
      visible: !ab.shadowMode
      x: ab.len - 1.5 * ab.u; y: -1.5 * ab.u
      width: 3 * ab.u; height: width; radius: width / 2
      color: "#e05a4f"
    }
    Rectangle {
      visible: !ab.shadowMode
      x: -5 * ab.u; y: -5 * ab.u
      width: 10 * ab.u; height: width; radius: width / 2
      color: "#b8b8b8"
      border.width: 1
      border.color: "#777777"
    }
  }

  // ======================================================================= UI
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    contentWidth: Style.space(260)
    contentHeight: Style.space(470)

    Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Qt.alpha(Color.popups.background, root.panelOpacity)

    Column {
      anchors.fill: parent
      anchors.margins: Style.spacing.panelPadding
      spacing: Style.spacing.panelGap

      // ---------------------------------------------------------- screen
      Rectangle {
        width: parent.width
        height: Style.space(140)
        radius: Style.space(6)
        color: Qt.rgba(0, 0, 0, root.screenOpacity)

        Column {
          anchors.fill: parent
          anchors.margins: Style.spacing.rowPaddingX
          spacing: Style.spacing.labelGap

          Text {
            text: root.live ? "VinylPod" : "No player"
            color: "#ffffff"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            opacity: 0.7
          }

          Row {
            width: parent.width
            spacing: Style.spacing.controlGap

            CircleArt {
              width: Style.space(48)
              height: Style.space(48)
              source: root.artSourceUrl
              fill: root.artDominant !== "" ? root.artDominant : Color.accent
              inset: Style.space(3)
            }

            Column {
              width: parent.width - Style.space(58)
              spacing: Style.spaceReal(2)

              Text {
                width: parent.width
                text: root.trackTitle !== "" ? root.trackTitle : "Nothing playing"
                color: "#ffffff"
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: root.trackArtist
                color: "#ffffff"
                opacity: 0.65
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                visible: text !== ""
              }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.spaceReal(3)
            radius: height / 2
            color: "#2b2b2b"

            Rectangle {
              width: parent.width * root.progress
              height: parent.height
              radius: height / 2
              color: Color.accent

              Behavior on width { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
            }
          }

          Row {
            width: parent.width

            Text {
              text: Model.formatTime(root.trackPosition)
              color: "#ffffff"
              opacity: 0.6
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            Item { width: parent.width - Style.space(90); height: 1 }
            Text {
              text: Model.formatTime(root.trackLength)
              color: "#ffffff"
              opacity: 0.6
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      Item { width: 1; height: Style.space(root.wheelDrop) }

      // ------------------------------------------------------- click wheel
      Item {
        id: wheelWrap
        width: Style.space(200)
        height: Style.space(200)
        anchors.horizontalCenter: parent.horizontalCenter

        // outer ring
        Rectangle {
          anchors.fill: parent
          radius: width / 2
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.lighter("#0a0a0a", 1.6) }
            GradientStop { position: 1.0; color: "#0a0a0a" }
          }
        }

        // spinning record — angle comes from the platter model (root.stepMotion):
        // quick spin-up, slow coast-down after pause.
        Item {
          id: vinyl
          anchors.fill: parent
          rotation: root.vinylAngle
          anchors.margins: Style.space(10)

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#111111"
          }

          Repeater {
            model: 7
            Rectangle {
              anchors.centerIn: parent
              width: vinyl.width - Style.space(20) - index * Style.space(10)
              height: width
              radius: width / 2
              color: "transparent"
              border.width: 1
              border.color: "#1f1f1f"
            }
          }
        }

        // label — album art, spins with the record
        Item {
          width: Style.space(78)
          height: Style.space(78)
          anchors.centerIn: parent
          rotation: vinyl.rotation

          CircleArt {
            anchors.fill: parent
            source: root.artSourceUrl
            fill: root.artDominant !== "" ? root.artDominant : Color.accent
            inset: Style.space(4)
          }

          Rectangle {
            width: Style.space(16)
            height: Style.space(16)
            radius: width / 2
            color: "#0a0a0a"
            anchors.centerIn: parent
          }
        }

        // specular sheen — stays put while the record turns under it, and the
        // highlight axis wobbles once per revolution like a slightly warped
        // pressing (ported from omarchy-vinyl's record.rs)
        Shape {
          id: sheen
          anchors.fill: vinyl
          layer.enabled: true
          layer.samples: 4

          ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillGradient: ConicalGradient {
              centerX: sheen.width / 2
              centerY: sheen.height / 2
              angle: 42 + 7 * Math.sin(root.vinylAngle * Math.PI / 180)
              GradientStop { position: 0.00; color: "#26ffffff" }
              GradientStop { position: 0.11; color: "#00ffffff" }
              GradientStop { position: 0.39; color: "#00ffffff" }
              GradientStop { position: 0.50; color: "#17ffffff" }
              GradientStop { position: 0.61; color: "#00ffffff" }
              GradientStop { position: 0.89; color: "#00ffffff" }
              GradientStop { position: 1.00; color: "#26ffffff" }
            }
            PathAngleArc {
              centerX: sheen.width / 2
              centerY: sheen.height / 2
              radiusX: sheen.width / 2
              radiusY: sheen.height / 2
              startAngle: 0
              sweepAngle: 360
            }
          }
        }

        // ---------------------------------------------------------- tonearm
        // Geometry is in 200-unit wheel space (u). Pivot sits off the top-right
        // of the record; arm length 105u. Angles come from the motion model.
        Item {
          id: tonearmRig
          anchors.fill: parent
          readonly property real u: wheelWrap.width / 200

          // arm shadow: three overlapping copies stand in for a blur, pushed
          // further out the higher the arm is lifted; only falls on the disc
          CircleClip {
            anchors.fill: parent
            anchors.margins: 10 * tonearmRig.u

            Repeater {
              model: 3
              ArmBody {
                readonly property real t: 0.55 + 0.45 * index / 2
                u: tonearmRig.u
                len: 105 * tonearmRig.u
                shadowMode: true
                x: (168 + (1.5 + 2.5 * root.armLift) * t) * tonearmRig.u
                y: (12 + (3.0 + 4.0 * root.armLift) * t) * tonearmRig.u
                rotation: root.armAngle
              }
            }
          }

          // pivot base plate
          Rectangle {
            x: 178 * tonearmRig.u - width / 2
            y: 22 * tonearmRig.u - height / 2
            width: 24 * tonearmRig.u
            height: width
            radius: width / 2
            color: "#2a2a2a"
            border.width: 1
            border.color: "#4a4a4a"
          }

          ArmBody {
            u: tonearmRig.u
            len: 105 * tonearmRig.u
            x: 178 * tonearmRig.u
            y: 22 * tonearmRig.u
            rotation: root.armAngle
          }
        }

        // hover detection for the whole wheel
        MouseArea {
          id: hoverArea
          anchors.fill: parent
          hoverEnabled: true
        }

        // dim scrim + transport controls, shown only on hover
        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: "#000000"
          opacity: hoverArea.containsMouse ? 0.55 : 0
          Behavior on opacity { NumberAnimation { duration: 140 } }
        }

        Row {
          anchors.centerIn: parent
          spacing: Style.space(24)
          opacity: hoverArea.containsMouse ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 140 } }

          Text {
            text: "\u23EE"
            color: "white"
            font.pixelSize: Style.font.iconLarge
            MouseArea { anchors.fill: parent; onClicked: root.skipPrevious() }
          }
          Text {
            text: root.playing ? "\u23F8" : "\u25B6"
            color: "white"
            font.pixelSize: Style.font.displayLarge
            MouseArea { anchors.fill: parent; onClicked: root.playPause() }
          }
          Text {
            text: "\u23ED"
            color: "white"
            font.pixelSize: Style.font.iconLarge
            MouseArea { anchors.fill: parent; onClicked: root.skipNext() }
          }
        }
      }
    }
    }
  }
}
