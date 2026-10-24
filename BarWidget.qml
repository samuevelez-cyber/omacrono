import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "s.omacrono"

  readonly property string stopwatchGlyph: "󱎫"

  readonly property var watchService: bar && bar.shell
    ? bar.shell.serviceFor(moduleName)
    : null

  // Show the time beside the icon once the stopwatch has started, or while a
  // label is being chosen at zero (which starts it).
  // Vertical bars are too narrow for text, so they keep the icon only.
  readonly property bool showTime: !!watchService
    && (!watchService.stopped || watchService.pendingStart)
    && !(bar && bar.vertical)

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false
  readonly property real openPanelIndicatorWidth: Style.bar.iconCanvas
  readonly property real openPanelIndicatorHeight: Style.bar.iconCanvas

  readonly property string tooltip: watchService
    ? (watchService.label !== "" ? watchService.label + " · " : "")
      + watchService.statusLabel + " · " + watchService.elapsedText
      + "\nRight-click: start/pause · Middle-click: reset"
    : "Omacrono"

  // Left opens the panel, right starts or pauses, middle resets.
  function handlePress(buttonCode) {
    if (buttonCode === Qt.RightButton) {
      if (watchService) watchService.startOrPause()
    } else if (buttonCode === Qt.MiddleButton) {
      if (watchService) watchService.reset()
    } else {
      toggle()
    }
  }

  function syncService() {
    if (watchService && typeof watchService.configure === "function")
      watchService.configure(settings)
    injectPanel()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = root.showTime ? timeButton : iconButton
    if ("hostWidget" in target) target.hostWidget = root
    if ("watchService" in target) target.watchService = root.watchService
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

  implicitWidth: showTime ? timeButton.implicitWidth : iconButton.implicitWidth
  implicitHeight: showTime ? timeButton.implicitHeight : iconButton.implicitHeight

  onBarChanged: Qt.callLater(syncService)
  onSettingsChanged: Qt.callLater(syncService)
  onWatchServiceChanged: Qt.callLater(syncService)
  onShowTimeChanged: injectPanel()
  Component.onCompleted: Qt.callLater(syncService)

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.syncService)
    }
  }

  BarIconButton {
    id: iconButton
    anchors.fill: parent
    visible: !root.showTime
    bar: root.bar
    text: root.stopwatchGlyph
    tooltipText: root.tooltip
    onPressed: function(buttonCode) { root.handlePress(buttonCode) }
  }

  WidgetButton {
    id: timeButton
    anchors.fill: parent
    visible: root.showTime
    bar: root.bar
    text: root.stopwatchGlyph + " " + (root.watchService ? root.watchService.shownText : "")
    active: !!root.watchService && (root.watchService.running || root.watchService.pendingStart)
    activeColor: Color.accent
    dimmed: !!root.watchService && root.watchService.paused
    tooltipText: root.tooltip
    onPressed: function(buttonCode) { root.handlePress(buttonCode) }
  }
}
