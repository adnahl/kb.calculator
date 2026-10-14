import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "CalcModel.js" as CalcModel

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool helpVisible: false
  property bool converterMode: false
  property bool unitConverterMode: false
  property bool dateCalculatorMode: false
  property string dateCalculationMode: "between"
  property string firstDate: ""
  property string secondDate: ""
  property int sourceBase: 10
  readonly property string baseName: sourceBase === 16 ? "Hexadecimal" : sourceBase === 2 ? "Binary" : "Decimal"
  property string expression: ""
  readonly property var conversion: CalcModel.convertInteger(root.expression, root.sourceBase)
  property string unitCategory: "length"
  property string fromUnit: "m"
  property string toUnit: "ft"
  property string unitPicker: ""
  readonly property string unitCategoryLabel: CalcModel.unitCategoryLabel(root.unitCategory)
  readonly property var unitConversion: CalcModel.convertUnit(root.expression, root.unitCategory, root.fromUnit, root.toUnit)
  readonly property var dateCalculation: CalcModel.calculateDate(root.dateCalculationMode, root.firstDate, root.secondDate)
  readonly property string result: root.dateCalculatorMode ? root.dateCalculation.value : root.unitConverterMode ? root.unitConversion.value : root.converterMode ? root.conversion.decimal : CalcModel.evaluate(root.expression) || ""

  readonly property string fontFamily: Style.font.menuFamily
  readonly property int cornerRadius: Style.cornerRadius
  readonly property int margin: Style.spacing.panelPadding

  readonly property int typeSize: Math.round(Style.font.bodySmall * 1.2)
  readonly property int fieldHeight: Math.max(Style.space(64), Math.round(root.typeSize * 3.8))
  readonly property int cardWidth: Math.min(Style.space(560), panel.width - Style.gapsOut * 2)

  // Keep long input readable; TextInput scrolls once it reaches the font floor.
  readonly property int fieldFontSize: {
    var available = input.width
    var size = Math.round(root.typeSize * 1.5)
    if (root.expression.length === 0)
      return size
    if (root.expression.length * size * 0.6 <= available)
      return size
    return Math.max(root.typeSize, Math.floor(available / root.expression.length / 0.6))
  }

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color scrim: Color.menu.scrim
  property var borderSpec: Border.flat(Color.menu.border, Math.max(1, Style.normalBorderWidth))

  property string status: ""

  Timer {
    id: statusTimer
    interval: 1200
    onTriggered: root.status = ""
  }

  function flash(message) {
    root.status = message
    statusTimer.restart()
  }

  function copyToClipboard(text, message) {
    if (!text)
      return
    Quickshell.execDetached(["wl-copy", "--", text])
    root.flash(message)
  }

  // Enter is the fast path and still closes the overlay: copy the result, done.
  // Ctrl+Enter copies the whole line and stays open, so the
  // calculation can be pasted somewhere and then edited further.
  function submit(withOperation) {
    if (root.dateCalculatorMode) {
      if (!root.dateCalculation.value)
        return
      root.copyToClipboard(withOperation ? root.dateCalculation.detail : root.dateCalculation.copy, withOperation ? "Calculation copied" : "Result copied")
      if (!withOperation)
        root.dismiss()
      return
    }
    if (!root.expression.trim()) {
      root.dismiss()
      return
    }
    if (!root.result)
      return
    var text
    if (root.unitConverterMode) {
      var converted = root.unitConversion.value + " " + CalcModel.unitSymbol(root.unitCategory, root.toUnit)
      text = withOperation ? root.expression + " " + CalcModel.unitSymbol(root.unitCategory, root.fromUnit) + " = " + converted : converted
    } else if (root.converterMode) {
      text = withOperation ? "DEC: " + root.conversion.decimal + "\nHEX: " + root.conversion.hexadecimal + "\nBIN: " + root.conversion.binary : root.result
    } else {
      text = withOperation ? root.expression + " = " + root.result : root.result
    }
    root.copyToClipboard(text, withOperation ? "All results copied" : "Result copied")
    if (!withOperation)
      root.dismiss()
  }

  function open(payloadJson) {
    root.opened = true
    root.helpVisible = false
    statusTimer.stop()
    root.status = ""
    root.setText("", 0)
    Qt.callLater(function () {
      if (root.dateCalculatorMode)
        firstDateInput.forceActiveFocus()
      else
        input.forceActiveFocus()
    })
  }

  function switchMode(mode) {
    var isBaseConverter = mode === 1
    var isUnitConverter = mode === 2
    var isDateCalculator = mode === 3
    if (root.converterMode !== isBaseConverter || root.unitConverterMode !== isUnitConverter || root.dateCalculatorMode !== isDateCalculator) {
      root.converterMode = isBaseConverter
      root.unitConverterMode = isUnitConverter
      root.dateCalculatorMode = isDateCalculator
      root.unitPicker = ""
      root.setText("", 0)
      root.status = ""
    }
    if (root.dateCalculatorMode)
      firstDateInput.forceActiveFocus()
    else
      input.forceActiveFocus()
  }

  function switchDateCalculationMode(mode) {
    root.dateCalculationMode = mode
    root.status = ""
    firstDateInput.forceActiveFocus()
  }

  function setDateToToday(field) {
    var date = new Date()
    var today = ("0000" + date.getFullYear()).slice(-4) + "-" + ("00" + (date.getMonth() + 1)).slice(-2) + "-" + ("00" + date.getDate()).slice(-2)
    if (field === "first") {
      root.firstDate = today
      firstDateInput.forceActiveFocus()
    } else if (field === "second" && root.dateCalculationMode === "between") {
      root.secondDate = today
      secondDateInput.forceActiveFocus()
    }
    root.status = ""
  }

  function handleDateInputKey(event) {
    if (event.key === Qt.Key_Escape) {
      root.handleEscape()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.submit(event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))
      event.accepted = true
    }
  }

  function switchUnitCategory(category) {
    var defaults = {
      length: ["m", "ft"],
      area: ["m2", "ft2"],
      volume: ["l", "gal"],
      temperature: ["c", "f"],
      mass: ["kg", "lb"]
    }
    var units = defaults[category]
    if (!units)
      return
    root.unitCategory = category
    root.fromUnit = units[0]
    root.toUnit = units[1]
    root.unitPicker = ""
    root.status = ""
    input.forceActiveFocus()
  }

  function handleEscape() {
    if (root.helpVisible)
      root.helpVisible = false
    else if (root.unitPicker)
      root.unitPicker = ""
    else if (root.dateCalculatorMode && (root.firstDate || root.secondDate)) {
      root.firstDate = ""
      root.secondDate = ""
    } else if (root.expression)
      root.setText("", 0)
    else
      root.dismiss()
    if (root.dateCalculatorMode)
      firstDateInput.forceActiveFocus()
    else
      input.forceActiveFocus()
  }

  function setText(value, cursor) {
    root.expression = value
    input.text = value
    input.cursorPosition = cursor
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "kb.calculator")
  }

  function toggle() {
    if (root.opened)
      root.dismiss()
    else
      root.open("{}")
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"
    WlrLayershell.namespace: "kb-calculator"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: Math.min(content.implicitHeight + card.contentTopInset + card.contentBottomInset, panel.height - Style.gapsOut * 2)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.margin
      Keys.onEscapePressed: root.handleEscape()

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Flickable {
        id: cardScroll
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Column {
          id: content
          width: cardScroll.width
          spacing: Style.spacing.lg

          Item {
            width: parent.width
            height: helpButton.implicitHeight

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Calculator"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Math.round(root.typeSize * 1.3)
              font.bold: true
            }

            Button {
              id: helpButton
              anchors.right: parent.right
              width: implicitHeight
              height: implicitHeight
              iconText: "?"
              iconSize: root.typeSize
              tooltipText: "Help"
              Accessible.name: "Calculator help"
              selected: root.helpVisible
              focusable: true
              fontFamily: root.fontFamily
              foreground: root.foreground
              onClicked: {
                root.helpVisible = !root.helpVisible
                if (root.dateCalculatorMode)
                  firstDateInput.forceActiveFocus()
                else
                  input.forceActiveFocus()
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.spacing.sm

            Repeater {
              model: ["Calculator", "Base converter", "Unit converter", "Date calculator"]
              Button {
                required property int index
                required property string modelData
                width: (content.width - Style.spacing.sm * 3) / 4
                text: modelData
                fontFamily: root.fontFamily
                fontSize: root.typeSize
                foreground: root.foreground
                selected: index === 0 ? !root.converterMode && !root.unitConverterMode && !root.dateCalculatorMode : index === 1 ? root.converterMode : index === 2 ? root.unitConverterMode : root.dateCalculatorMode
                focusable: true
                Accessible.name: modelData
                onClicked: root.switchMode(index)
              }
            }
          }

          Row {
            id: baseSelector
            width: parent.width
            visible: root.converterMode
            spacing: Style.spacing.sm

            Repeater {
              model: [
                {
                  label: "Decimal",
                  base: 10
                },
                {
                  label: "Hexadecimal",
                  base: 16
                },
                {
                  label: "Binary",
                  base: 2
                }
              ]
              Button {
                required property var modelData
                width: (content.width - Style.spacing.sm * 2) / 3
                text: modelData.label
                fontFamily: root.fontFamily
                fontSize: root.typeSize
                foreground: root.foreground
                selected: root.sourceBase === modelData.base
                focusable: true
                tooltipText: "Interpret input as " + modelData.label.toLowerCase()
                Accessible.name: modelData.label + " input"
                onClicked: {
                  root.sourceBase = modelData.base
                  root.status = ""
                  input.forceActiveFocus()
                }
              }
            }
          }

          Row {
            width: parent.width
            visible: root.unitConverterMode
            spacing: Style.spacing.sm

            Repeater {
              model: CalcModel.unitCategories()
              Button {
                required property var modelData
                width: (content.width - Style.spacing.sm * 4) / 5
                text: modelData.label
                fontFamily: root.fontFamily
                fontSize: root.typeSize
                foreground: root.foreground
                selected: root.unitCategory === modelData.id
                focusable: true
                Accessible.name: modelData.label
                onClicked: root.switchUnitCategory(modelData.id)
              }
            }
          }

          Row {
            width: parent.width
            visible: root.unitConverterMode
            spacing: Style.spacing.sm

            Button {
              width: (parent.width - parent.spacing) / 2
              text: "From: " + CalcModel.unitSymbol(root.unitCategory, root.fromUnit)
              fontFamily: root.fontFamily
              fontSize: root.typeSize
              foreground: root.foreground
              selected: root.unitPicker === "from"
              focusable: true
              tooltipText: "Convert from " + CalcModel.unitName(root.unitCategory, root.fromUnit)
              Accessible.name: "From " + CalcModel.unitName(root.unitCategory, root.fromUnit)
              onClicked: root.unitPicker = root.unitPicker === "from" ? "" : "from"
            }

            Button {
              width: (parent.width - parent.spacing) / 2
              text: "To: " + CalcModel.unitSymbol(root.unitCategory, root.toUnit)
              fontFamily: root.fontFamily
              fontSize: root.typeSize
              foreground: root.foreground
              selected: root.unitPicker === "to"
              focusable: true
              tooltipText: "Convert to " + CalcModel.unitName(root.unitCategory, root.toUnit)
              Accessible.name: "To " + CalcModel.unitName(root.unitCategory, root.toUnit)
              onClicked: root.unitPicker = root.unitPicker === "to" ? "" : "to"
            }
          }

          Flow {
            id: unitPickerFlow
            width: parent.width
            visible: root.unitConverterMode && root.unitPicker !== ""
            spacing: Style.spacing.sm

            Repeater {
              model: CalcModel.unitsForCategory(root.unitCategory)
              Button {
                required property var modelData
                width: Math.min(implicitWidth, unitPickerFlow.width)
                text: modelData.name
                fontFamily: root.fontFamily
                fontSize: root.typeSize
                foreground: root.foreground
                selected: root.unitPicker === "from" ? root.fromUnit === modelData.id : root.toUnit === modelData.id
                focusable: true
                Accessible.name: modelData.name
                onClicked: {
                  if (root.unitPicker === "from")
                    root.fromUnit = modelData.id
                  else
                    root.toUnit = modelData.id
                  root.unitPicker = ""
                  root.status = ""
                  input.forceActiveFocus()
                }
              }
            }
          }

          Row {
            width: parent.width
            visible: root.dateCalculatorMode
            spacing: Style.spacing.sm

            Repeater {
              model: [
                { id: "between", label: "Days between" },
                { id: "add", label: "Add / subtract days" }
              ]
              Button {
                required property var modelData
                width: (parent.width - parent.spacing) / 2
                text: modelData.label
                fontFamily: root.fontFamily
                fontSize: root.typeSize
                foreground: root.foreground
                selected: root.dateCalculationMode === modelData.id
                focusable: true
                Accessible.name: modelData.label
                onClicked: root.switchDateCalculationMode(modelData.id)
              }
            }
          }

          Row {
            width: parent.width
            visible: root.dateCalculatorMode
            spacing: Style.spacing.sm

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.sm

              Text {
                width: parent.width
                text: root.dateCalculationMode === "between" ? "Start date" : "Date"
                textFormat: Text.PlainText
                color: root.foreground
                opacity: 0.65
                font.family: root.fontFamily
                font.pixelSize: root.typeSize
              }

              Rectangle {
                width: parent.width
                height: root.fieldHeight
                radius: root.cornerRadius
                color: Color.menu.selectedBackground
                border.width: 1
                border.color: firstDateInput.activeFocus ? Color.menu.selectedText : Color.menu.border

                TextInput {
                  id: firstDateInput
                  anchors.left: parent.left
                  anchors.right: firstTodayButton.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.leftMargin: root.margin
                  anchors.rightMargin: Style.spacing.sm
                  verticalAlignment: TextInput.AlignVCenter
                  horizontalAlignment: TextInput.AlignHCenter
                  text: root.firstDate
                  color: root.foreground
                  font.family: "monospace"
                  font.pixelSize: root.typeSize
                  selectByMouse: true
                  clip: true
                  Accessible.name: root.dateCalculationMode === "between" ? "Start date in YYYY-MM-DD format" : "Date in YYYY-MM-DD format"
                  Keys.priority: Keys.BeforeItem
                  Keys.onPressed: function (event) { root.handleDateInputKey(event) }
                  onTextEdited: {
                    root.firstDate = text
                    root.status = ""
                  }
                }

                Button {
                  id: firstTodayButton
                  anchors.right: parent.right
                  anchors.rightMargin: root.margin
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Today"
                  fontFamily: root.fontFamily
                  fontSize: Math.round(root.typeSize * 0.8)
                  foreground: root.foreground
                  opacity: 0.7
                  focusable: true
                  Accessible.name: "Set date to today"
                  onClicked: root.setDateToToday("first")
                }

                Text {
                  anchors.left: parent.left
                  anchors.right: firstTodayButton.left
                  anchors.rightMargin: Style.spacing.sm
                  anchors.verticalCenter: parent.verticalCenter
                  horizontalAlignment: Text.AlignHCenter
                  visible: !root.firstDate
                  text: "YYYY-MM-DD"
                  color: root.foreground
                  opacity: 0.45
                  font.family: "monospace"
                  font.pixelSize: root.typeSize
                }
              }
            }

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.sm

              Text {
                width: parent.width
                text: root.dateCalculationMode === "between" ? "End date" : "Days (+/-)"
                textFormat: Text.PlainText
                color: root.foreground
                opacity: 0.65
                font.family: root.fontFamily
                font.pixelSize: root.typeSize
              }

              Rectangle {
                width: parent.width
                height: root.fieldHeight
                radius: root.cornerRadius
                color: Color.menu.selectedBackground
                border.width: 1
                border.color: secondDateInput.activeFocus ? Color.menu.selectedText : Color.menu.border

                TextInput {
                  id: secondDateInput
                  anchors.left: parent.left
                  anchors.right: secondTodayButton.visible ? secondTodayButton.left : parent.right
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.leftMargin: root.margin
                  anchors.rightMargin: secondTodayButton.visible ? Style.spacing.sm : root.margin
                  verticalAlignment: TextInput.AlignVCenter
                  horizontalAlignment: TextInput.AlignHCenter
                  text: root.secondDate
                  color: root.foreground
                  font.family: "monospace"
                  font.pixelSize: root.typeSize
                  selectByMouse: true
                  clip: true
                  Accessible.name: root.dateCalculationMode === "between" ? "End date in YYYY-MM-DD format" : "Number of days to add or subtract"
                  Keys.priority: Keys.BeforeItem
                  Keys.onPressed: function (event) { root.handleDateInputKey(event) }
                  onTextEdited: {
                    root.secondDate = text
                    root.status = ""
                  }
                }

                Button {
                  id: secondTodayButton
                  anchors.right: parent.right
                  anchors.rightMargin: root.margin
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.dateCalculationMode === "between"
                  text: "Today"
                  fontFamily: root.fontFamily
                  fontSize: Math.round(root.typeSize * 0.8)
                  foreground: root.foreground
                  opacity: 0.7
                  focusable: visible
                  Accessible.name: "Set end date to today"
                  onClicked: root.setDateToToday("second")
                }

                Text {
                  anchors.left: parent.left
                  anchors.right: secondTodayButton.visible ? secondTodayButton.left : parent.right
                  anchors.rightMargin: secondTodayButton.visible ? Style.spacing.sm : 0
                  anchors.verticalCenter: parent.verticalCenter
                  horizontalAlignment: Text.AlignHCenter
                  visible: !root.secondDate
                  text: root.dateCalculationMode === "between" ? "YYYY-MM-DD" : "e.g. 7 or -3"
                  color: root.foreground
                  opacity: 0.45
                  font.family: "monospace"
                  font.pixelSize: root.typeSize
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.dateCalculatorMode
            text: root.dateCalculationMode === "between" ? "Elapsed days (the start date is not counted)" : "Use a negative number to subtract days"
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: root.typeSize
          }

          Text {
            width: parent.width
            visible: !root.dateCalculatorMode
            text: root.unitConverterMode ? root.unitCategoryLabel + " value" : root.converterMode ? root.baseName + " integer" : "Expression"
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.65
            font.family: root.fontFamily
            font.pixelSize: root.typeSize
          }

          Rectangle {
            width: parent.width
            height: root.fieldHeight
            visible: !root.dateCalculatorMode
            radius: root.cornerRadius
            color: Color.menu.selectedBackground
            border.width: 1
            border.color: input.activeFocus ? Color.menu.selectedText : Color.menu.border

            Text {
              id: placeholder
              anchors.centerIn: parent
              visible: !root.expression
              textFormat: Text.PlainText
              text: root.unitConverterMode ? "e.g. 12.5" : root.converterMode ? (root.sourceBase === 16 ? "e.g. 0xFF" : root.sourceBase === 2 ? "e.g. 101010" : "e.g. 255") : "e.g. (128 + 64) / 2"
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              // Proportional to the field so the hierarchy survives any scale, with a floor
              // so a small input never makes the hint unreadable.
              font.pixelSize: Math.max(6, Math.round(root.fieldFontSize * 0.75))
            }

            TextInput {
              id: input
              anchors.fill: parent
              anchors.margins: root.margin
              verticalAlignment: TextInput.AlignVCenter
              horizontalAlignment: TextInput.AlignHCenter
              text: root.expression
              clip: true
              onTextEdited: {
                var pretty = root.converterMode || root.unitConverterMode ? {
                  text: text,
                  cursor: cursorPosition
                } : CalcModel.prettify(text, cursorPosition)
                if (pretty.text !== text) {
                  text = pretty.text
                  cursorPosition = pretty.cursor
                }
                root.expression = text
                // Editing invalidates whatever the last copy confirmation said.
                root.status = ""
              }
              color: root.foreground
              selectionColor: Qt.rgba(Color.menu.selectedText.r, Color.menu.selectedText.g, Color.menu.selectedText.b, 0.35)
              selectedTextColor: root.foreground
              font.family: root.fontFamily
              font.pixelSize: root.fieldFontSize
              selectByMouse: true
              focus: true
              Accessible.name: root.converterMode ? root.baseName + " integer input" : root.unitConverterMode ? root.unitCategoryLabel + " value" : "Arithmetic expression"

              Keys.priority: Keys.BeforeItem
              Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Escape) {
                  root.handleEscape()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.submit(event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))
                  event.accepted = true
                } else if (!root.converterMode && !root.unitConverterMode && (event.text === "(" || event.text === ")") && input.selectedText.length > 0) {
                  // Wrap the selection instead of replacing it.
                  var from = input.selectionStart
                  var to = input.selectionEnd
                  root.setText(root.expression.slice(0, from) + "(" + input.selectedText + ")" + root.expression.slice(to), to + 2)
                  event.accepted = true
                } else if (!root.converterMode && !root.unitConverterMode && (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) && !(event.modifiers & Qt.ControlModifier) && input.selectedText.length === 0) {
                  // A parenthesis and its partner disappear together.
                  var index = event.key === Qt.Key_Backspace ? input.cursorPosition - 1 : input.cursorPosition
                  var pair = index >= 0 ? CalcModel.deleteParenPair(root.expression, index) : null
                  if (pair) {
                    root.setText(pair.text, pair.cursor)
                    event.accepted = true
                  }
                }
              }
            }
          }

          Rectangle {
            id: divider
            width: parent.width
            height: 1
            visible: !root.converterMode && !root.unitConverterMode && !root.dateCalculatorMode && root.result.length > 0
            color: root.foreground
            opacity: 0.15
          }

          Text {
            id: result
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            visible: !root.converterMode && !root.unitConverterMode && !root.dateCalculatorMode && root.result.length > 0
            text: "= " + root.result
            color: Color.menu.selectedText
            font.family: root.fontFamily
            font.pixelSize: Math.round(root.typeSize * 2)
            font.bold: true
            elide: Text.ElideMiddle
          }

          Column {
            id: conversionResults
            width: parent.width
            visible: root.converterMode
            spacing: Style.spacing.sm

            Text {
              width: parent.width
              visible: root.conversion.error.length > 0
              text: root.conversion.error
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: root.typeSize
            }

            Repeater {
              model: [
                {
                  label: "DEC",
                  key: "decimal"
                },
                {
                  label: "HEX",
                  key: "hexadecimal"
                },
                {
                  label: "BIN",
                  key: "binary"
                }
              ]
              Rectangle {
                id: conversionRow
                required property var modelData
                readonly property string value: root.conversion[modelData.key]
                width: conversionResults.width
                height: Math.max(Style.space(48), copyButton.implicitHeight + Style.spacing.sm * 2)
                color: Color.menu.selectedBackground
                radius: root.cornerRadius

                Text {
                  id: baseLabel
                  anchors.left: parent.left
                  anchors.leftMargin: root.margin
                  anchors.verticalCenter: parent.verticalCenter
                  width: root.typeSize * 3
                  text: conversionRow.modelData.label
                  color: Color.menu.selectedText
                  font.family: root.fontFamily
                  font.pixelSize: root.typeSize
                  font.bold: true
                }

                TextInput {
                  anchors.left: baseLabel.right
                  anchors.right: copyButton.left
                  anchors.margins: Style.spacing.sm
                  anchors.verticalCenter: parent.verticalCenter
                  text: conversionRow.value
                  color: root.foreground
                  font.family: "monospace"
                  font.pixelSize: root.typeSize
                  readOnly: true
                  selectByMouse: true
                  clip: true
                  selectionColor: Color.menu.selectedBackground
                  selectedTextColor: Color.menu.selectedText
                  Accessible.name: conversionRow.modelData.label + " result"
                }

                Button {
                  id: copyButton
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.sm
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Copy"
                  fontFamily: root.fontFamily
                  fontSize: root.typeSize
                  foreground: root.foreground
                  enabled: conversionRow.value.length > 0
                  opacity: enabled ? 1 : 0.4
                  focusable: enabled
                  Accessible.name: "Copy " + conversionRow.modelData.label + " result"
                  onClicked: root.copyToClipboard(conversionRow.value, conversionRow.modelData.label + " copied")
                }
              }
            }
          }

          Column {
            width: parent.width
            visible: root.unitConverterMode
            spacing: Style.spacing.sm

            Text {
              width: parent.width
              visible: root.unitConversion.error.length > 0
              text: root.unitConversion.error
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: root.typeSize
            }

            Text {
              width: parent.width
              visible: root.unitConversion.value.length > 0
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: root.unitConversion.value + " " + CalcModel.unitSymbol(root.unitCategory, root.toUnit)
              color: Color.menu.selectedText
              font.family: root.fontFamily
              font.pixelSize: Math.round(root.typeSize * 1.8)
              font.bold: true
              elide: Text.ElideMiddle
            }

            Button {
              anchors.horizontalCenter: parent.horizontalCenter
              visible: root.unitConversion.value.length > 0
              text: "Copy"
              fontFamily: root.fontFamily
              fontSize: root.typeSize
              foreground: root.foreground
              focusable: visible
              Accessible.name: "Copy converted value"
              onClicked: root.copyToClipboard(root.unitConversion.value + " " + CalcModel.unitSymbol(root.unitCategory, root.toUnit), "Result copied")
            }
          }

          Column {
            width: parent.width
            visible: root.dateCalculatorMode
            spacing: Style.spacing.sm

            Text {
              width: parent.width
              visible: root.dateCalculation.error.length > 0
              text: root.dateCalculation.error
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: root.typeSize
            }

            Text {
              width: parent.width
              visible: root.dateCalculation.value.length > 0
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: root.dateCalculation.value
              color: Color.menu.selectedText
              font.family: root.fontFamily
              font.pixelSize: Math.round(root.typeSize * 1.8)
              font.bold: true
              elide: Text.ElideMiddle
            }

            Button {
              anchors.horizontalCenter: parent.horizontalCenter
              visible: root.dateCalculation.value.length > 0
              text: "Copy"
              fontFamily: root.fontFamily
              fontSize: root.typeSize
              foreground: root.foreground
              focusable: visible
              Accessible.name: "Copy date calculation result"
              onClicked: root.copyToClipboard(root.dateCalculation.copy, "Result copied")
            }
          }

          Rectangle {
            id: helpPanel
            width: parent.width
            visible: root.helpVisible
            radius: root.cornerRadius
            color: Color.menu.selectedBackground
            border.width: 1
            border.color: Color.menu.border
            height: Math.min(helpContent.implicitHeight + root.margin * 2, Style.space(280), panel.height * 0.4)
            onVisibleChanged: if (visible)
              helpScroll.contentY = 0

            Flickable {
              id: helpScroll
              anchors.fill: parent
              anchors.margins: root.margin
              contentWidth: width
              contentHeight: helpContent.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              flickableDirection: Flickable.VerticalFlick

              Column {
                id: helpContent
                width: helpScroll.width
                spacing: Style.spacing.lg

                Repeater {
                  model: [
                    {
                      title: "Keyboard shortcuts",
                      body: "<p><b>Enter</b><br>Copy the result and close.</p>" + "<p><b>Ctrl+Enter / Shift+Enter</b><br>Copy the expression and result without closing.</p>" + "<p><b>Esc</b><br>Close help or the unit picker first, then clear the input or close the calculator.</p>"
                    },
                    {
                      title: "Base converter",
                      body: "<p>Select the input base: <b>Decimal</b>, <b>Hexadecimal</b>, or <b>Binary</b>. All three results update as you type.</p>" + "<p>Integers only, with optional <b>+ / -</b> signs. Hexadecimal accepts <b>0x</b>; binary accepts <b>0b</b>. Prefixes must match the selected base.</p>" + "<p>Large integers are converted exactly. Negative results use a minus sign, not two's complement.</p>" + "<p><b>Enter</b> copies decimal and closes. <b>Ctrl+Enter / Shift+Enter</b> copies all three bases without closing. Use <b>Copy</b> beside a result to copy that base.</p>" + "<p>Changing the input base reinterprets the current text. Switching modes clears the input.</p>"
                    },
                    {
                      title: "Unit converter",
                      body: "<p>Choose a category and select the <b>From</b> and <b>To</b> units. Results update as you type. Length, area, volume, temperature, and mass/weight are supported, including metric and US customary units.</p>" + "<p>Enter a number using a decimal point or comma. Expressions are not supported. Temperatures below absolute zero are rejected.</p>" + "<p><b>Enter</b> copies the converted value and closes. <b>Ctrl+Enter / Shift+Enter</b> copies the input and converted value without closing. Use <b>Copy</b> to copy the converted value.</p>"
                    },
                    {
                      title: "Date calculator",
                      body: "<p>Enter dates in <b>YYYY-MM-DD</b> format. <b>Days between</b> calculates elapsed days, without counting the start date. <b>Add / subtract days</b> accepts a positive or negative whole number.</p>" + "<p><b>Enter</b> copies the result and closes. <b>Ctrl+Enter / Shift+Enter</b> copies the calculation details without closing.</p>"
                    },
                    {
                      title: "Arithmetic",
                      body: "<p><b>Basic operators</b><br>Add <i>+</i>, subtract <i>- or −</i>, multiply <i>*, × or x</i>, divide <i>/ or ÷</i>.</p>" + "<p><b>Powers and grouping</b><br>Use <i>^ or **</i>, parentheses, and unary <i>+ / -</i> signs.</p>" + "<p><b>Implicit multiplication</b><br><i>2(3+4), 2pi, 2√9</i></p>" + "<p><b>Percentages</b><br><i>50%, 200*15%, 80+10%, 80-25%</i></p>" + "<p><b>Remainder (modulo)</b><br><i>17 % 5</i></p>"
                    },
                    {
                      title: "Functions and notation",
                      body: "<p><b>Square root / Absolute value</b><br><i>sqrt(16) or √16 / abs(-7)</i></p>" + "<p><b>Rounding</b><br><i>round(2.5), round(3.14159; 2)</i></p>" + "<p><b>Round down / Round up</b><br><i>floor(2.9) / ceil(2.1)</i></p>" + "<p><b>Constants</b><br><i>pi, π, e</i></p>" + "<p><b>Decimals / Thousands</b><br><i>0.5 or 0,5 / 1'000</i></p>"
                    }
                  ]

                  Row {
                    required property var modelData
                    width: helpContent.width
                    spacing: Style.spacing.lg

                    Text {
                      width: (parent.width - parent.spacing) * 0.3
                      text: modelData.title
                      textFormat: Text.PlainText
                      wrapMode: Text.WordWrap
                      horizontalAlignment: Text.AlignLeft
                      color: Color.menu.selectedText
                      font.family: root.fontFamily
                      font.pixelSize: root.typeSize
                      font.bold: true
                    }

                    Text {
                      width: (parent.width - parent.spacing) * 0.7
                      text: modelData.body
                      textFormat: Text.RichText
                      wrapMode: Text.WordWrap
                      horizontalAlignment: Text.AlignLeft
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: root.typeSize
                    }
                  }
                }
              }
            }
          }

          Text {
            id: confirmation
            width: parent.width
            height: implicitHeight
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: root.status || (root.dateCalculatorMode ? "Enter: copy result and close  /  Ctrl+Enter: copy calculation" : root.unitConverterMode ? "Enter: copy converted value and close  /  Ctrl+Enter: copy input and result" : root.converterMode ? "Enter: copy decimal and close  /  Ctrl+Enter: copy all" : "Enter: copy and close  /  Ctrl+Enter: copy expression")
            wrapMode: Text.WordWrap
            opacity: root.status ? 1 : 0.6
            color: root.status ? Color.menu.selectedText : root.foreground
            font.family: root.fontFamily
            font.pixelSize: root.typeSize
          }
        }
      }
    }
  }
}
