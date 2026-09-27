import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Letter V on the bar. The panel is loaded here (Omarchy bar-widget contract):
// Bar.findPanelWidget looks for open/close/opened on THIS root, and KeyboardPanel
// in VinylPod.qml is what actually paints the popout. Shelling out to
// `omarchy-shell toggle` never opened the nested panel — that's why V did nothing.
BarWidget {
  id: root

  moduleName: "maiosx.vinylpod"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }
  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }
  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("VinylPod.qml")
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "maiosx.vinylpod"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function playPause(): string {
      return panelLoader.item && panelLoader.item.playPause() ? "ok" : "unhandled"
    }
    function next(): string {
      return panelLoader.item && panelLoader.item.skipNext() ? "ok" : "unhandled"
    }
    function previous(): string {
      return panelLoader.item && panelLoader.item.skipPrevious() ? "ok" : "unhandled"
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "V"
    tooltipText: root.opened ? "Hide VinylPod" : "VinylPod"
    active: root.opened || (panelLoader.item && panelLoader.item.playing === true)

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        if (panelLoader.item) panelLoader.item.playPause()
        return
      }
      if (mouseButton === Qt.MiddleButton) {
        if (panelLoader.item) panelLoader.item.skipNext()
        return
      }
      root.toggle()
    }
  }
}
