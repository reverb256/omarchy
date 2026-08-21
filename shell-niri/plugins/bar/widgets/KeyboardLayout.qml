import QtQuick
import Quickshell.Io
import Niri
import qs.Ui
import qs.Commons
import "KeyboardLayoutModel.js" as KeyboardLayoutModel

BarWidget {
  id: root
  moduleName: "omarchy.keyboard-layout"

  // niri reports the configured xkb layouts and the active index directly
  // (KeyboardLayoutsChanged / KeyboardLayoutSwitched), so there is no hyprctl
  // device scan: Niri.keyboardLayouts.names is the layout list and
  // Niri.keyboardLayouts.currentName is the active one. Niri names are xkb
  // codes ("us"), which shortLabel renders as "US" via its fallback; the
  // xkbcli briefs table still resolves any full description niri may report.
  property string layoutFull: ""
  property var layoutBriefs: ({})
  readonly property string layoutLabel: KeyboardLayoutModel.shortLabel(layoutFull, layoutBriefs)

  readonly property var layouts: Niri.keyboardLayouts
  readonly property bool multipleLayouts: layouts !== null && layouts.names && layouts.names.length > 1

  function cycleLayout() {
    Niri.switchKeyboardLayoutNext()
  }

  Component.onCompleted: {
    briefsProc.running = true
    layoutFull = layouts ? (layouts.currentName || "") : ""
  }

  Connections {
    target: Niri.keyboardLayouts
    function onCurrentIndexChanged() {
      root.layoutFull = root.layouts.currentName || ""
    }
  }

  Process {
    id: briefsProc
    command: ["xkbcli", "list", "--load-exotic"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.layoutBriefs = KeyboardLayoutModel.layoutBriefs(text)
    }
  }

  visible: layoutLabel !== "" && multipleLayouts
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.layoutLabel
    fontSize: Style.font.caption
    horizontalMargin: 6
    tooltipText: root.layoutFull
    onPressed: function() { root.cycleLayout() }
  }
}
