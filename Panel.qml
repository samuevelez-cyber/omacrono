import QtQuick
import qs.Commons
import qs.Ui
import "StopwatchModel.js" as StopwatchModel

Panel {
  id: root
  moduleName: "s.omacrono"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var watchService: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: Color.popups.text
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color activeColor: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string glyphStopwatch: "󱎫"
  readonly property string glyphPlay: ""
  readonly property string glyphPause: ""
  readonly property string glyphReset: "󰑐"
  readonly property string glyphTag: ""

  readonly property int actionCount: 3
  property int selectedAction: 0
  property bool cursorActive: true

  // Label editing: what's typed, and which suggestion is highlighted (-1 = the typed text).
  property bool editingLabel: false
  property double labelEditStartedMs: 0
  property string labelQuery: ""
  property int suggestionIndex: -1
  readonly property int maxVisibleSuggestions: 5

  // Ticks fast only while the panel is open and counting, for the hundredths.
  property double fastNowMs: Date.now()

  readonly property bool ready: !!watchService && watchService.initialized
  readonly property bool isRunning: ready && watchService.running
  readonly property bool isStopped: !ready || watchService.stopped
  readonly property string currentLabel: ready ? watchService.label : ""
  // At zero, the label box counts from when it opened: choosing a label starts
  // the clock from then, so the time shown is the time that will be kept.
  readonly property bool pendingStart: editingLabel && ready && watchService.pendingStart
  readonly property bool counting: isRunning || pendingStart
  readonly property double heroMs: !ready ? 0
    : pendingStart ? Math.max(0, fastNowMs - watchService.labelPendingSinceMs)
    : StopwatchModel.elapsedMilliseconds(watchService.watchState, isRunning ? fastNowMs : watchService.nowMs)

  readonly property var knownLabels: ready ? watchService.knownLabels : []
  readonly property var suggestions: StopwatchModel.suggestLabels(knownLabels, labelQuery)
  readonly property string typedLabel: StopwatchModel.canonicalLabel(knownLabels, labelQuery)
  readonly property bool typedIsNew: typedLabel !== "" && knownLabels.indexOf(typedLabel) === -1

  function open() {
    selectedAction = 0
    cursorActive = true
    editingLabel = false
    fastNowMs = Date.now()
    controller.show()
  }

  function close() {
    if (editingLabel) cancelEditingLabel()
    controller.hide()
  }

  // However the panel closes, an unfinished label edit is cancelled.
  onOpenedChanged: if (!opened && editingLabel) cancelEditingLabel()

  function toggle() {
    if (opened) close()
    else open()
  }

  function actionEnabled(index) {
    if (!ready) return false
    if (index === 1) return !watchService.stopped
    return true
  }

  function selectAction(delta) {
    cursorActive = true
    selectedAction = ((selectedAction + delta) % actionCount + actionCount) % actionCount
  }

  function activate(index) {
    if (!actionEnabled(index)) return
    if (index === 0) watchService.startOrPause()
    else if (index === 1) watchService.reset()
    else if (index === 2) startEditingLabel()
  }

  function actionHovered(index, hovered) {
    if (!hovered) return
    cursorActive = true
    selectedAction = index
  }

  function startEditingLabel() {
    if (!ready) return
    editingLabel = true
    labelEditStartedMs = Date.now()
    fastNowMs = labelEditStartedMs
    if (watchService.stopped) watchService.labelPendingSinceMs = labelEditStartedMs
    Qt.callLater(function() {
      labelField.text = ""
      labelField.forceActiveFocus()
      root.suggestionIndex = -1
    })
  }

  // Enter takes the highlighted suggestion, otherwise the typed text (in its
  // earlier spelling if it matches a known label). Empty text keeps the label.
  // On a clock at zero, choosing a label also starts it.
  function commitLabel() {
    var chosen = suggestionIndex >= 0 && suggestionIndex < suggestions.length
      ? suggestions[suggestionIndex]
      : typedLabel
    if (chosen !== "" && watchService) watchService.setLabel(chosen, labelEditStartedMs)
    cancelEditingLabel()
  }

  function removeLabel() {
    if (watchService) watchService.setLabel("")
    cancelEditingLabel()
  }

  function pickSuggestion(index) {
    suggestionIndex = index
    commitLabel()
  }

  function moveSuggestion(delta) {
    if (suggestions.length === 0) return
    suggestionIndex = Math.max(-1, Math.min(suggestions.length - 1, suggestionIndex + delta))
    if (suggestionIndex >= 0) suggestionList.positionViewAtIndex(suggestionIndex, ListView.Contain)
  }

  // Tab fills the field with the highlighted (or first) suggestion to keep typing from there.
  function completeSuggestion() {
    if (suggestions.length === 0) return
    labelField.text = suggestions[Math.max(0, suggestionIndex)]
    labelField.cursorPosition = labelField.text.length
  }

  function cancelEditingLabel() {
    editingLabel = false
    if (watchService) watchService.labelPendingSinceMs = 0
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  Timer {
    interval: 40
    repeat: true
    running: root.opened && root.counting
    onTriggered: root.fastNowMs = Date.now()
  }

  component SmallCaps: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.letterSpacing: 1
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLabel

      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.selectAction(dx)
        else if (dy !== 0) root.selectAction(dy)
      }
      onActivateRequested: root.activate(root.selectedAction)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(14)

        // ---- Hero: icon + big time on the left; label and status on the right.
        Item {
          width: parent.width
          height: Math.max(heroLeft.height, heroRight.height)

          Row {
            id: heroLeft
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(14)

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: root.glyphStopwatch
              color: root.counting ? root.activeColor : root.foreground
              font.family: root.fontFamily
              // Decorative hero glyph, like the weather panel's condition icon.
              font.pixelSize: 52
              Behavior on color { ColorAnimation { duration: 200 } }
            }

            Row {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                id: heroTime
                textFormat: Text.PlainText
                text: StopwatchModel.formatMs(root.heroMs)
                color: root.foreground
                font.family: root.fontFamily
                // Hero read-out; deliberately oversized, outside the Style.font.* scale.
                font.pixelSize: 52
                font.bold: true
              }
              Text {
                textFormat: Text.PlainText
                text: StopwatchModel.formatHundredths(root.heroMs)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                anchors.baseline: heroTime.baseline
              }
            }
          }

          Column {
            id: heroRight
            anchors.right: parent.right
            anchors.rightMargin: Style.space(20)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(190)
            spacing: Style.space(10)

            // Click the label to rename what you're timing, like the weather location.
            Row {
              anchors.right: parent.right
              spacing: Style.space(6)

              TapHandler { onTapped: root.startEditingLabel() }
              HoverHandler { cursorShape: Qt.PointingHandCursor }

              Text {
                textFormat: Text.PlainText
                text: root.glyphTag
                color: root.editingLabel ? root.activeColor : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }
              SmallCaps {
                text: root.currentLabel !== "" ? root.currentLabel.toUpperCase() : "ADD LABEL"
                color: root.editingLabel ? root.activeColor : root.dim
                font.pixelSize: Style.font.body
                font.italic: root.currentLabel === ""
                elide: Text.ElideRight
                width: Math.min(implicitWidth, heroRight.width - Style.space(20))
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Row {
              anchors.right: parent.right
              spacing: Style.space(6)

              Rectangle {
                width: Style.space(7)
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: root.isRunning ? root.activeColor : root.dim
                opacity: root.isRunning ? 1 : 0.6

                SequentialAnimation on opacity {
                  running: root.opened && root.isRunning
                  loops: Animation.Infinite
                  NumberAnimation { to: 0.3; duration: 900; easing.type: Easing.InOutSine }
                  NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                }
              }
              SmallCaps {
                text: root.ready ? root.watchService.statusLabel.toUpperCase() : "LOADING"
                color: root.isRunning ? root.activeColor : root.dim
              }
            }
          }
        }

        // ---- Label editor: type to filter every label used before, or write a new one.
        Column {
          visible: root.editingLabel
          width: parent.width - Style.space(32)
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(6)

          TextField {
            id: labelField
            width: parent.width
            placeholderText: root.currentLabel !== ""
              ? "Type to change \u201c" + root.currentLabel + "\u201d"
              : "What are you timing?"
            foreground: root.foreground
            font.family: root.fontFamily
            maximumLength: StopwatchModel.MaxLabelLength

            onTextChanged: {
              root.labelQuery = text
              root.suggestionIndex = -1
              suggestionList.positionViewAtBeginning()
            }

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.cancelEditingLabel()
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.commitLabel()
              } else if (event.key === Qt.Key_Down) {
                root.moveSuggestion(1)
              } else if (event.key === Qt.Key_Up) {
                root.moveSuggestion(-1)
              } else if (event.key === Qt.Key_Tab) {
                root.completeSuggestion()
              } else if (event.key === Qt.Key_Delete && text === "" && root.currentLabel !== "") {
                root.removeLabel()
              } else {
                return
              }
              event.accepted = true
            }
          }

          ListView {
            id: suggestionList
            width: parent.width
            visible: count > 0
            height: Math.min(count, root.maxVisibleSuggestions) * Style.space(28)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.suggestions

            delegate: Rectangle {
              required property var modelData
              required property int index
              readonly property bool highlighted: index === root.suggestionIndex
              width: ListView.view.width
              height: Style.space(28)
              radius: Style.cornerRadius
              color: highlighted || rowMouse.containsMouse
                ? Style.hoverFillFor(root.foreground, root.activeColor)
                : "transparent"

              Row {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)

                Text {
                  textFormat: Text.PlainText
                  text: root.glyphTag
                  color: parent.parent.highlighted ? root.activeColor : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  textFormat: Text.PlainText
                  text: modelData
                  color: parent.parent.highlighted ? root.activeColor : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pickSuggestion(index)
              }
            }
          }

          SmallCaps {
            width: parent.width
            elide: Text.ElideRight
            font.pixelSize: Style.font.caption
            text: {
              var enter = root.pendingStart ? "ENTER: START " : "ENTER: "
              if (root.suggestionIndex >= 0)
                return enter + (root.pendingStart ? "WITH" : "USE") + " HIGHLIGHTED · ESC: CANCEL"
              if (root.typedLabel === "")
                return root.currentLabel !== ""
                  ? "↑↓ PICK · DEL: REMOVE LABEL · ESC: CANCEL"
                  : "↑↓ PICK · ESC: CANCEL"
              if (root.typedIsNew) return enter + "NEW LABEL \"" + root.typedLabel.toUpperCase() + "\" · ↑↓ PICK · TAB: COMPLETE"
              return enter + root.typedLabel.toUpperCase() + " · ↑↓ PICK · TAB: COMPLETE"
            }
          }
        }

        Rectangle {
          width: parent.width
          height: Style.spacing.hairline
          color: root.foreground
          opacity: 0.12
        }

        // ---- Actions.
        Row {
          id: actions
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)

          Repeater {
            model: [
              { icon: root.isRunning ? root.glyphPause : root.glyphPlay,
                text: root.isRunning ? "Pause" : (root.isStopped ? "Start" : "Resume") },
              { icon: root.glyphReset, text: "Reset" },
              { icon: root.glyphTag, text: "Label" }
            ]

            Button {
              required property var modelData
              required property int index
              iconText: modelData.icon
              text: modelData.text
              foreground: root.foreground
              accent: root.activeColor
              iconSize: Style.font.iconLarge
              enabled: root.actionEnabled(index)
              opacity: enabled ? 1 : 0.35
              hasCursor: root.cursorActive && root.selectedAction === index && !root.editingLabel
              onHovered: function(value) { root.actionHovered(index, value) }
              onClicked: root.activate(index)
            }
          }
        }
      }
    }
  }
}
