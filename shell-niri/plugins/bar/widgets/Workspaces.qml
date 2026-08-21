import QtQuick
import QtQuick.Layouts
import Niri
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  // niri workspaces are indexed 1..N (matching `niri msg action
  // focus-workspace <index>`). qml-niri exposes them as a list model whose
  // `get(row)` returns a map with index/id/name/output/isActive/isFocused/
  // activeWindowId roles. `occupied` approximates Hyprland's "has toplevels"
  // via the workspace's active-window id (niri does not report a per-workspace
  // window count over IPC).
  function workspaceAt(index) {
    var model = Niri.workspaces
    for (var i = 0; i < model.count; i++) {
      var w = model.get(i)
      if (Number(w.index) === index) return w
    }

    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var model = Niri.workspaces

    for (var i = 0; i < model.count; i++) {
      var idx = Number(model.get(i).index)
      if (idx > 0 && idx <= 10 && ids.indexOf(idx) === -1) ids.push(idx)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(index) {
    // focusWorkspace takes a workspace index (1-based), not a niri window id.
    Niri.focusWorkspace(index)
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceAt(modelData)
        readonly property bool occupied: workspace !== null && Number(workspace.activeWindowId) > 0
        readonly property bool focused: workspace !== null && workspace.isFocused === true

        bar: root.bar
        text: focused ? "\uDB85\uDCFB" : (modelData === 10 ? "0" : String(modelData))
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }
  }
}
