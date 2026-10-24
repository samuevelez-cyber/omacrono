import QtQuick
import Quickshell
import Quickshell.Io
import "StopwatchModel.js" as StopwatchModel

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME")
    || ((Quickshell.env("HOME") || "") + "/.local/state")
  readonly property string stateDir: stateHome + "/omarchy"
  readonly property string statePath: stateDir + "/omacrono.json"
  readonly property string historyPath: stateDir + "/omacrono-history.json"

  property var watchState: StopwatchModel.stoppedState(Date.now())
  property var history: StopwatchModel.emptyHistory()
  property double nowMs: Date.now()
  property bool stateFileLoaded: false
  property bool historyFileLoaded: false
  property bool initialized: false
  property bool stateDirReady: false
  property bool savePending: false
  property bool historySavePending: false
  property string loadedStateText: ""
  property string loadedHistoryText: ""

  readonly property string status: watchState.status
  readonly property string statusLabel: StopwatchModel.statusLabel(status)
  readonly property string label: watchState.label || ""
  readonly property double elapsedMs: StopwatchModel.elapsedMilliseconds(watchState, nowMs)
  readonly property int elapsedSeconds: Math.floor(elapsedMs / 1000)
  readonly property string elapsedText: StopwatchModel.formatElapsed(elapsedSeconds)
  readonly property bool stopped: status === StopwatchModel.StatusStopped
  readonly property bool running: status === StopwatchModel.StatusRunning
  readonly property bool paused: status === StopwatchModel.StatusPaused
  readonly property var knownLabels: StopwatchModel.knownLabels(history, label)

  // Set by the panel while its label box is open on a clock at zero. Choosing a
  // label starts the clock from that moment, so the bar already counts from it.
  property double labelPendingSinceMs: 0
  readonly property bool pendingStart: stopped && labelPendingSinceMs > 0
  readonly property double shownMs: pendingStart ? Math.max(0, nowMs - labelPendingSinceMs) : elapsedMs
  readonly property string shownText: StopwatchModel.formatMs(shownMs)

  // The bar widget calls this; Omacrono has no settings yet.
  function configure(settings) {}

  function parseSaved(text, what) {
    if (String(text || "").trim() === "") return null
    try {
      return JSON.parse(text)
    } catch (error) {
      console.warn("Omacrono: ignoring invalid persisted " + what + ":", error)
      return null
    }
  }

  function initializeIfReady() {
    if (initialized || !stateFileLoaded || !historyFileLoaded) return
    var now = Date.now()
    history = StopwatchModel.sanitizeHistory(parseSaved(loadedHistoryText, "history"))
    var restored = StopwatchModel.sanitizeState(parseSaved(loadedStateText, "stopwatch state"), now)
    initialized = true
    setState(restored, true)
  }

  function setState(next, persist) {
    watchState = next
    nowMs = Date.now()
    if (persist) scheduleSave()
  }

  // Records the running stretch up to now before the state changes shape.
  function recordSegment(now) {
    var segment = StopwatchModel.closedSegment(watchState, now)
    if (!segment) return
    history = StopwatchModel.appendSegment(history, segment, now)
    historySavePending = true
    scheduleSave()
  }

  function startOrPause() {
    if (!initialized) return
    var now = Date.now()
    if (running) {
      recordSegment(now)
      setState(StopwatchModel.pause(watchState, now), true)
    } else {
      setState(StopwatchModel.start(watchState, now), true)
    }
  }

  function reset() {
    if (!initialized || stopped) return
    var now = Date.now()
    recordSegment(now)
    setState(StopwatchModel.reset(watchState, now), true)
  }

  // sinceMs: when the label box was opened; a clock at zero starts from then.
  function setLabel(text, sinceMs) {
    if (!initialized) return
    // Reuse an earlier spelling when the same label is typed in another case.
    var next = StopwatchModel.canonicalLabel(knownLabels, text)
    var now = Date.now()
    labelPendingSinceMs = 0
    if (stopped && next !== "") {
      setState(StopwatchModel.startWithLabel(watchState, next, sinceMs, now), true)
      return
    }
    if (next === label) return
    recordSegment(now)
    setState(StopwatchModel.setLabel(watchState, next, now), true)
  }

  function scheduleSave() {
    if (!initialized) return
    savePending = true
    saveTimer.restart()
  }

  function flushState() {
    if (!savePending || !stateDirReady) return
    savePending = false
    var snapshot = StopwatchModel.serializableState(watchState, Date.now())
    stateFile.setText(JSON.stringify(snapshot, null, 2) + "\n")
    if (historySavePending) {
      historySavePending = false
      historyFile.setText(JSON.stringify(history) + "\n")
    }
  }

  Component.onCompleted: stateDirProcess.running = true

  // Commands for keybindings and scripts:
  //   omarchy-shell s.omacrono toggle | reset | label "Client A" | status
  IpcHandler {
    target: "s.omacrono"
    function toggle(): string { root.startOrPause(); return root.status }
    function reset(): string { root.reset(); return root.status }
    function label(text: string): string { root.setLabel(text); return root.label }
    function status(): string {
      return JSON.stringify({ status: root.status, elapsed: root.elapsedText, label: root.label })
    }
  }

  Timer {
    interval: 250
    repeat: true
    running: root.initialized && (root.running || root.pendingStart)
    onTriggered: root.nowMs = Date.now()
  }

  Timer {
    id: saveTimer
    interval: 100
    repeat: false
    onTriggered: root.flushState()
  }

  Process {
    id: stateDirProcess
    command: ["mkdir", "-p", root.stateDir]
    onExited: function(exitCode) {
      root.stateDirReady = exitCode === 0
      if (!root.stateDirReady) {
        console.warn("Omacrono: could not create the state directory")
        return
      }
      root.flushState()
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.loadedStateText = text()
      root.stateFileLoaded = true
      root.initializeIfReady()
    }
    onLoadFailed: {
      root.loadedStateText = ""
      root.stateFileLoaded = true
      root.initializeIfReady()
    }
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.loadedHistoryText = text()
      root.historyFileLoaded = true
      root.initializeIfReady()
    }
    onLoadFailed: {
      root.loadedHistoryText = ""
      root.historyFileLoaded = true
      root.initializeIfReady()
    }
  }
}
