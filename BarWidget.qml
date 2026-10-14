import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "kb.calculator"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰃬"
    slotSize: Style.bar.statusSlot
    tooltipText: "Calculator and converters"

    onPressed: function (b) {
      if (!root.bar || !root.bar.shell) return
      root.bar.shell.toggle(root.moduleName, "{}")
    }
  }
}