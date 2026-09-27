import QtQuick
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
  readonly property real trackPosition: {
    if (!live || !player.positionSupported) return 0
    var pos = Math.max(0, player.position)
    return trackLength > 0 ? Math.min(pos, trackLength) : pos
  }
  readonly property real progress: trackLength > 0 ? Math.max(0, Math.min(1, trackPosition / trackLength)) : 0

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
  }
}
