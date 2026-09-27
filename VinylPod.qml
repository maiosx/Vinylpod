import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons
import "Model.js" as Model

// VinylPod — a floating now-playing panel (kind: "panel", the Quattro kind
// for a persistent/summoned floating window such as an OSD).
//
// Extends the same `Panel` base component Spotmarchy's bar-widget popout
// extends, which is where `open()`/`close()`/`toggle()`, the `setting(key,
// default)` accessor, and the IPC/summon plumbing all come from — nothing
// here reimplements them. Unlike Spotmarchy's popout, this panel has no
// invoking bar widget, so it never reads `bar` (which Spotmarchy only reads
// defensively as `bar ? ... : fallback` anyway) — theming instead comes
// straight from the qs.Commons singletons (`Color`, `Style`) documented for
// any shell QML, not just bar widgets.
//
// Song data and album-art colour extraction reuse Spotmarchy's Model.js
// unchanged (same MPRIS matching + art-probe pipeline), the same reuse
// pattern already used for the vinyl-player overlay.
Panel {
  id: root

  moduleName: "maiosx.vinylpod"
  ipcTarget: "maiosx.vinylpod"
  // Base only wires open/close/toggle; this adds transport calls on the
  // same IPC target, so it owns the whole handler — same call Spotmarchy
  // makes for the same reason.
  manageIpc: false

  // ---------------------------------------------------------------- settings
  readonly property string corner: String(setting("corner", "bottom-right"))
  readonly property int margin: Style.space(Number(setting("margin", 24)))
  readonly property bool showWhenClosed: setting("showWhenClosed", false) === true

  readonly property bool anchorTop: corner === "top-left" || corner === "top-right"
  readonly property bool anchorLeft: corner === "top-left" || corner === "bottom-left"

  // NOTE: I don't have Panel's own source, only Spotmarchy's usage of it as
  // a bar-widget popout (which anchors relative to the invoking widget, not
  // a screen corner). Whether Panel exposes its own corner/margin anchoring
  // for a standalone summon, or expects the surrounding PanelWindow-style
  // anchors/margins grouped properties instead, isn't in the template I
  // was given — the two blocks below (`anchors`/`margins`) are Quickshell's
  // own PanelWindow convention and may need adjusting to whatever Panel
  // actually forwards. Check qs/Ui/Panel.qml in your Omarchy checkout
  // (docs point at shell/services/PluginRegistry.qml for the full schema)
  // before shipping.
  anchors {
    top: anchorTop
    bottom: !anchorTop
    left: anchorLeft
    right: !anchorLeft
  }
  margins {
    top: margin
    bottom: margin
    left: margin
    right: margin
  }

  implicitWidth: Style.space(260)
  implicitHeight: Style.space(470)

  // ------------------------------------------------------------------ player
  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: Model.findSpotify(players)
  readonly property bool live: player !== null && player !== undefined
  readonly property bool playing: live && player.isPlaying === true

  readonly property string trackTitle: live ? String(player.trackTitle || "") : ""
  readonly property string trackArtist: live ? String(player.trackArtist || "") : ""
  readonly property string artUrl: live ? String(player.trackArtUrl || "") : ""

  readonly property real trackLength: live && player.lengthSupported ? Math.max(0, player.length) : 0
  readonly property real trackPosition: {
    if (!live || !player.positionSupported) return 0
    var pos = Math.max(0, player.position)
    return trackLength > 0 ? Math.min(pos, trackLength) : pos
  }
  readonly property real progress: trackLength > 0 ? Math.max(0, Math.min(1, trackPosition / trackLength)) : 0

  readonly property bool shown: live || showWhenClosed
  visible: shown

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

  // ======================================================================= UI
  Rectangle {
    id: body
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Color.popups.background
    border.width: 1
    border.color: Color.popups.border

    Column {
      anchors.fill: parent
      anchors.margins: Style.spacing.panelPadding
      spacing: Style.spacing.panelGap

      // ---------------------------------------------------------- screen
      Rectangle {
        width: parent.width
        height: Style.space(140)
        radius: Style.cornerRadius
        color: Color.background

        Column {
          anchors.fill: parent
          anchors.margins: Style.spacing.rowPaddingX
          spacing: Style.spacing.labelGap

          Text {
            text: root.live ? "VinylPod" : "No player"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            opacity: 0.7
          }

          Row {
            width: parent.width
            spacing: Style.spacing.controlGap

            Rectangle {
              width: Style.space(48)
              height: Style.space(48)
              radius: width / 2
              color: root.artDominant !== "" ? root.artDominant : Color.accent
              clip: true

              Image {
                anchors.fill: parent
                anchors.margins: Style.space(3)
                visible: root.artSourceUrl !== ""
                source: root.artSourceUrl
                fillMode: Image.PreserveAspectCrop
              }
            }

            Column {
              width: parent.width - Style.space(58)
              spacing: Style.spaceReal(2)

              Text {
                width: parent.width
                text: root.trackTitle !== "" ? root.trackTitle : "Nothing playing"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: root.trackArtist
                color: Color.foreground
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
            color: Qt.darker(Color.background, 1.4)

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
              color: Color.foreground
              opacity: 0.6
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            Item { width: parent.width - Style.space(90); height: 1 }
            Text {
              text: Model.formatTime(root.trackLength)
              color: Color.foreground
              opacity: 0.6
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

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

        // spinning record — rotation runs only while playing, and simply
        // holds its last angle when paused/stopped.
        Item {
          id: vinyl
          anchors.fill: parent
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

          RotationAnimation {
            target: vinyl
            property: "rotation"
            from: 0
            to: 360
            duration: 4800
            loops: Animation.Infinite
            running: root.playing
          }
        }

        // label — album art, spins with the record
        Item {
          width: Style.space(78)
          height: Style.space(78)
          anchors.centerIn: parent
          rotation: vinyl.rotation

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: root.artDominant !== "" ? root.artDominant : Color.accent
            clip: true

            Image {
              anchors.fill: parent
              anchors.margins: Style.space(4)
              visible: root.artSourceUrl !== ""
              source: root.artSourceUrl
              fillMode: Image.PreserveAspectCrop
            }
          }

          Rectangle {
            width: Style.space(16)
            height: Style.space(16)
            radius: width / 2
            color: "#0a0a0a"
            anchors.centerIn: parent
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

  IpcHandler {
    target: "maiosx.vinylpod"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function playPause(): string { return root.playPause() ? "ok" : "unhandled" }
    function next(): string { return root.skipNext() ? "ok" : "unhandled" }
    function previous(): string { return root.skipPrevious() ? "ok" : "unhandled" }
  }
}
