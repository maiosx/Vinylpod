import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "Model.js" as Model

// VinylPod — a floating now-playing panel for Omarchy/Quickshell.
//
// The click wheel doubles as a turntable: it spins for real while a track
// plays, the album art sits on the label like a 45, and prev/play-pause/next
// fade in over the record itself on hover instead of living in a permanent
// row of buttons.
//
// Song data and album-art colour extraction reuse Spotmarchy's Model.js
// unchanged (same MPRIS matching + art probe pipeline as the bar widget),
// following the same approach as the vinyl-player overlay.
//
// NOTE: `corner` / `margin` / `showWhenClosed` are declared in manifest.json
// as user-configurable settings, but this file reads them as plain QML
// properties with the manifest's own defaults rather than through an Omarchy
// settings API — the uploaded template only covers a bar widget, so the
// settings-binding call (`setting("key", default)` in Panel.qml) belongs to
// a base component that isn't part of this template. Wire these three
// properties to whatever that call turns out to be before shipping.

PanelWindow {
    id: root

    // ---- settings (see NOTE above) ----
    readonly property string corner: "bottom-right"
    readonly property int margin: 24
    readonly property bool showWhenClosed: false

    readonly property bool anchorTop: corner === "top-left" || corner === "top-right"
    readonly property bool anchorLeft: corner === "top-left" || corner === "bottom-left"

    implicitWidth: 260
    implicitHeight: 470
    color: "transparent"
    exclusiveZone: 0

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

    // ------------------------------------------------------------- player
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
    // Unchanged from Spotmarchy's Panel.qml: Qt can display the cover but
    // not tell us its colour, so an ImageMagick probe (via Model.js) reads a
    // downloaded copy and hands back a dominant colour + a local file to
    // display from, never the raw remote/art URL directly.
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

    // ------------------------------------------------------------ actions
    function playPause() {
        if (!live) return
        if (player.canTogglePlaying) player.togglePlaying()
        else if (playing && player.canPause) player.pause()
        else if (!playing && player.canPlay) player.play()
    }
    function skipNext() { if (live && player.canGoNext) player.next() }
    function skipPrevious() { if (live && player.canGoPrevious) player.previous() }

    // ================================================================ UI
    Rectangle {
        id: body
        anchors.fill: parent
        radius: 34
        border.width: 1
        border.color: "#8f8c82"
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#d7d4cc" }
            GradientStop { position: 1.0; color: "#b9b6ac" }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 18

            // ---------------------------------------------------- screen
            Rectangle {
                width: parent.width
                height: 140
                radius: 10
                color: "#0a0d08"

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    Text {
                        text: root.live ? "VinylPod" : "No player"
                        color: "#9fae86"
                        font.pixelSize: 9
                    }

                    Row {
                        width: parent.width
                        spacing: 10

                        Rectangle {
                            width: 48
                            height: 48
                            radius: 24
                            color: root.artDominant !== "" ? root.artDominant : "#7c2430"
                            clip: true

                            Image {
                                anchors.fill: parent
                                anchors.margins: 3
                                visible: root.artSourceUrl !== ""
                                source: root.artSourceUrl
                                fillMode: Image.PreserveAspectCrop
                            }
                        }

                        Column {
                            width: parent.width - 58
                            spacing: 2

                            Text {
                                width: parent.width
                                text: root.trackTitle !== "" ? root.trackTitle : "Nothing playing"
                                color: "#dfeccb"
                                font.pixelSize: 12
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: root.trackArtist
                                color: "#9fae86"
                                font.pixelSize: 10.5
                                elide: Text.ElideRight
                                visible: text !== ""
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 3
                        radius: 2
                        color: "#1c2417"

                        Rectangle {
                            width: parent.width * root.progress
                            height: parent.height
                            radius: 2
                            color: "#dfeccb"

                            Behavior on width { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
                        }
                    }

                    Row {
                        width: parent.width

                        Text {
                            text: Model.formatTime(root.trackPosition)
                            color: "#9fae86"
                            font.pixelSize: 8.5
                        }
                        Item { width: parent.width - 90; height: 1 }
                        Text {
                            text: Model.formatTime(root.trackLength)
                            color: "#9fae86"
                            font.pixelSize: 8.5
                        }
                    }
                }
            }

            // ----------------------------------------------- click wheel
            Item {
                id: wheelWrap
                width: 200
                height: 200
                anchors.horizontalCenter: parent.horizontalCenter

                // outer ring
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#2a2a2a" }
                        GradientStop { position: 1.0; color: "#0a0a0a" }
                    }
                }

                // spinning record — rotation runs only while playing, and
                // simply holds its last angle when paused/stopped.
                Item {
                    id: vinyl
                    anchors.fill: parent
                    anchors.margins: 10

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "#111111"
                    }

                    Repeater {
                        model: 7
                        Rectangle {
                            anchors.centerIn: parent
                            width: vinyl.width - 20 - index * 10
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
                    width: 78
                    height: 78
                    anchors.centerIn: parent
                    rotation: vinyl.rotation

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: root.artDominant !== "" ? root.artDominant : "#c9a227"
                        clip: true

                        Image {
                            anchors.fill: parent
                            anchors.margins: 4
                            visible: root.artSourceUrl !== ""
                            source: root.artSourceUrl
                            fillMode: Image.PreserveAspectCrop
                        }
                    }

                    Rectangle {
                        width: 16
                        height: 16
                        radius: 8
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
                    spacing: 24
                    opacity: hoverArea.containsMouse ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 140 } }

                    Text {
                        text: "\u23EE"
                        color: "white"
                        font.pixelSize: 20
                        MouseArea { anchors.fill: parent; onClicked: root.skipPrevious() }
                    }
                    Text {
                        text: root.playing ? "\u23F8" : "\u25B6"
                        color: "white"
                        font.pixelSize: 26
                        MouseArea { anchors.fill: parent; onClicked: root.playPause() }
                    }
                    Text {
                        text: "\u23ED"
                        color: "white"
                        font.pixelSize: 20
                        MouseArea { anchors.fill: parent; onClicked: root.skipNext() }
                    }
                }
            }
        }
    }
}
