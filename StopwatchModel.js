// Pure stopwatch-state helpers shared by QML and the Node test suite.
//
// The live state holds the running counter and its label. Finished stretches
// of running time ("segments") go to a separate history. The panel only reads
// the label names from it, for suggestions; the times are kept so a report can
// be built later without having lost the past.

var StateVersion = 2
var HistoryVersion = 1
var StatusStopped = "stopped"
var StatusRunning = "running"
var StatusPaused = "paused"
var MaxLabelLength = 40
var HistoryKeepDays = 90
var DayMs = 24 * 60 * 60 * 1000

function finiteNumber(value, fallback) {
  var parsed = Number(value)
  return isFinite(parsed) ? parsed : fallback
}

function isStatus(value) {
  return value === StatusStopped || value === StatusRunning || value === StatusPaused
}

function statusLabel(status) {
  if (status === StatusRunning) return "Running"
  if (status === StatusPaused) return "Paused"
  return "Ready"
}

function normalizeLabel(text) {
  return String(text || "").replace(/\s+/g, " ").trim().slice(0, MaxLabelLength)
}

function stoppedState(nowMs, label) {
  return {
    version: StateVersion,
    status: StatusStopped,
    accumulatedMs: 0,
    startedAtMs: 0,
    label: normalizeLabel(label),
    updatedAtMs: finiteNumber(nowMs, 0)
  }
}

function elapsedMilliseconds(state, nowMs) {
  if (!state) return 0
  var accumulated = Math.max(0, finiteNumber(state.accumulatedMs, 0))
  if (state.status !== StatusRunning) return accumulated
  var since = finiteNumber(nowMs, 0) - finiteNumber(state.startedAtMs, 0)
  return accumulated + Math.max(0, since)
}

function elapsedSeconds(state, nowMs) {
  return Math.floor(elapsedMilliseconds(state, nowMs) / 1000)
}

function start(state, nowMs) {
  if (state && state.status === StatusRunning) return state
  var now = finiteNumber(nowMs, 0)
  var next = state ? cloneState(state) : stoppedState(now)
  next.status = StatusRunning
  next.startedAtMs = now
  next.updatedAtMs = now
  return next
}

function pause(state, nowMs) {
  if (!state || state.status !== StatusRunning) return state
  var now = finiteNumber(nowMs, 0)
  var next = cloneState(state)
  next.accumulatedMs = elapsedMilliseconds(state, now)
  next.status = StatusPaused
  next.startedAtMs = 0
  next.updatedAtMs = now
  return next
}

// Back to zero; the label stays so the next run keeps tracking the same task.
function reset(state, nowMs) {
  return stoppedState(nowMs, state ? state.label : "")
}

// While running, a new label starts a fresh segment without touching the counter.
function setLabel(state, label, nowMs) {
  var now = finiteNumber(nowMs, 0)
  var next = cloneState(state)
  next.label = normalizeLabel(label)
  if (state.status === StatusRunning) {
    next.accumulatedMs = elapsedMilliseconds(state, now)
    next.startedAtMs = now
  }
  next.updatedAtMs = now
  return next
}

// Picking a label on a clock at zero also starts it. The clock counts from
// startMs (when the label box was opened) so the time spent choosing counts too.
function startWithLabel(state, label, startMs, nowMs) {
  var now = finiteNumber(nowMs, 0)
  var since = finiteNumber(startMs, now)
  if (since <= 0 || since > now) since = now
  return start(setLabel(state, label, now), since)
}

// The stretch of running time that ends now, or null when nothing is running.
function closedSegment(state, nowMs) {
  if (!state || state.status !== StatusRunning) return null
  var start = finiteNumber(state.startedAtMs, 0)
  var end = finiteNumber(nowMs, 0)
  if (end - start < 1000) return null
  return { label: normalizeLabel(state.label), startMs: start, endMs: end }
}

// Every label ever used, most recent first, each in its most recent spelling.
function knownLabels(history, currentLabel) {
  var seen = {}
  var result = []
  var candidates = [currentLabel]
  var sessions = (history && history.sessions) || []
  for (var i = sessions.length - 1; i >= 0; i--) candidates.push(sessions[i].label)
  for (var j = 0; j < candidates.length; j++) {
    var label = normalizeLabel(candidates[j])
    var key = label.toLowerCase()
    if (label === "" || seen[key]) continue
    seen[key] = true
    result.push(label)
  }
  return result
}

// Labels matching what's typed: those starting with it first, then those with
// a word starting with it, then any that contain it. Order within each group
// stays most-recent-first. An empty query lists everything.
function suggestLabels(labels, query) {
  var needle = normalizeLabel(query).toLowerCase()
  if (needle === "") return labels.slice()
  var starts = [], wordStarts = [], contains = []
  for (var i = 0; i < labels.length; i++) {
    var hay = labels[i].toLowerCase()
    var at = hay.indexOf(needle)
    if (at === 0) starts.push(labels[i])
    else if (at > 0 && hay.search(new RegExp("[^a-z0-9]" + escapeRegExp(needle))) >= 0) wordStarts.push(labels[i])
    else if (at > 0) contains.push(labels[i])
  }
  return starts.concat(wordStarts, contains)
}

// The existing spelling of a label typed in any case, or the text as typed.
function canonicalLabel(labels, text) {
  var label = normalizeLabel(text)
  var key = label.toLowerCase()
  for (var i = 0; i < labels.length; i++)
    if (labels[i].toLowerCase() === key) return labels[i]
  return label
}

function escapeRegExp(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

function emptyHistory() {
  return { version: HistoryVersion, sessions: [] }
}

function sanitizeHistory(raw) {
  if (!raw || Number(raw.version) !== HistoryVersion || !Array.isArray(raw.sessions))
    return emptyHistory()
  var sessions = []
  for (var i = 0; i < raw.sessions.length; i++) {
    var item = raw.sessions[i] || {}
    var start = finiteNumber(item.startMs, NaN)
    var end = finiteNumber(item.endMs, NaN)
    if (isFinite(start) && isFinite(end) && end > start)
      sessions.push({ label: normalizeLabel(item.label), startMs: start, endMs: end })
  }
  return { version: HistoryVersion, sessions: sessions }
}

function appendSegment(history, segment, nowMs) {
  var next = { version: HistoryVersion, sessions: (history.sessions || []).slice() }
  if (segment) next.sessions.push(segment)
  var cutoff = finiteNumber(nowMs, 0) - HistoryKeepDays * DayMs
  next.sessions = next.sessions.filter(function(item) { return item.endMs >= cutoff })
  return next
}

function sanitizeState(raw, nowMs) {
  var now = finiteNumber(nowMs, 0)
  var version = raw ? Number(raw.version) : 0
  if (!raw || (version !== 1 && version !== StateVersion) || !isStatus(raw.status))
    return stoppedState(now)
  if (raw.status === StatusStopped) return stoppedState(now, raw.label)

  var startedAt = Math.max(0, finiteNumber(raw.startedAtMs, 0))
  // A start time in the future means the clock jumped; treat it as starting now.
  if (raw.status === StatusRunning && (startedAt === 0 || startedAt > now)) startedAt = now

  return {
    version: StateVersion,
    status: raw.status,
    accumulatedMs: Math.max(0, finiteNumber(raw.accumulatedMs, 0)),
    startedAtMs: raw.status === StatusRunning ? startedAt : 0,
    label: normalizeLabel(raw.label),
    updatedAtMs: Math.max(0, finiteNumber(raw.updatedAtMs, now))
  }
}

function serializableState(state, nowMs) {
  var next = cloneState(state)
  next.updatedAtMs = finiteNumber(nowMs, 0)
  return next
}

function pad(value) {
  return String(value).padStart(2, "0")
}

function formatElapsed(seconds) {
  var value = Math.max(0, Math.floor(finiteNumber(seconds, 0)))
  var hours = Math.floor(value / 3600)
  var minutes = Math.floor((value % 3600) / 60)
  var remainder = value % 60
  if (hours > 0) return hours + ":" + pad(minutes) + ":" + pad(remainder)
  return pad(minutes) + ":" + pad(remainder)
}

function formatMs(ms) {
  return formatElapsed(finiteNumber(ms, 0) / 1000)
}

function formatHundredths(ms) {
  return "." + pad(Math.floor(Math.max(0, finiteNumber(ms, 0)) % 1000 / 10))
}

function cloneState(state) {
  var copy = {}
  for (var key in state) copy[key] = state[key]
  return copy
}
