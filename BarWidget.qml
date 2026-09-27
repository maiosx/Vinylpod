import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Minimal bar chip: letter "V" that toggles the VinylPod floating panel.
BarWidget {
  id: root

  moduleName: "maiosx.vinylpod"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "V"
    tooltipText: "VinylPod"
    active: false

    onPressed: function(mouseButton) {
      if (!root.bar) return
      // Same IPC the README keybinding uses.
      root.bar.run("omarchy-shell shell toggle maiosx.vinylpod '{}'")
    }
  }
}
