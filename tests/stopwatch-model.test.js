#!/usr/bin/env node

const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

process.env.TZ = "UTC"
const source = fs.readFileSync(path.join(__dirname, "..", "StopwatchModel.js"), "utf8")
const model = {}
vm.createContext(model)
vm.runInContext(source, model, { filename: "StopwatchModel.js" })

// ---- Counting, pausing, resuming.
let state = model.stoppedState(0)
assert.equal(state.status, model.StatusStopped)
assert.equal(model.elapsedSeconds(state, 999999), 0, "a stopped stopwatch reads zero")

state = model.start(state, 1000)
assert.equal(model.elapsedSeconds(state, 66000), 65)
assert.equal(model.start(state, 5000), state, "starting a running stopwatch changes nothing")

state = model.pause(state, 66000)
assert.equal(model.elapsedSeconds(state, 900000), 65, "paused time does not count")

state = model.start(state, 900000)
assert.equal(model.elapsedSeconds(state, 910000), 75, "resuming continues from the paused time")

// ---- Restarts.
let restored = model.sanitizeState(JSON.parse(JSON.stringify(state)), 970000)
assert.equal(model.elapsedSeconds(restored, 970000), 135, "a running stopwatch keeps counting across restarts")

restored = model.sanitizeState(model.pause(state, 910000), 5000000)
assert.equal(restored.status, model.StatusPaused)
assert.equal(model.elapsedSeconds(restored, 5000000), 75, "a paused stopwatch stays paused across restarts")

const v1 = { version: 1, status: "running", accumulatedMs: 0, startedAtMs: 1000, updatedAtMs: 1000 }
restored = model.sanitizeState(v1, 11000)
assert.equal(model.elapsedSeconds(restored, 11000), 10, "version 1 state files still load")
assert.equal(restored.label, "")

const future = { version: 2, status: "running", accumulatedMs: 1000, startedAtMs: 9e12, updatedAtMs: 0 }
assert.equal(model.elapsedSeconds(model.sanitizeState(future, 1000), 1000), 1, "a future start time is clamped")
assert.equal(model.sanitizeState(null, 0).status, model.StatusStopped)
assert.equal(model.sanitizeState({ version: 99, status: "running" }, 0).status, model.StatusStopped)

// ---- Reset.
state = model.reset(model.setLabel(model.start(model.stoppedState(0), 0), "Client A", 300000), 310000)
assert.equal(state.status, model.StatusStopped)
assert.equal(model.elapsedSeconds(state, 400000), 0)
assert.equal(state.label, "Client A", "reset keeps the label for the next run")

// ---- Labels and segments.
assert.equal(model.normalizeLabel("  Client   A  "), "Client A")
assert.equal(model.normalizeLabel("x".repeat(80)).length, model.MaxLabelLength)

state = model.start(model.stoppedState(0, "Client A"), 1000)
let segment = model.closedSegment(state, 61000)
assert.deepEqual({ ...segment }, { label: "Client A", startMs: 1000, endMs: 61000 })
const relabeled = model.setLabel(state, "Client B", 61000)
assert.equal(model.elapsedSeconds(relabeled, 121000), 120, "changing the label never changes the counter")
assert.equal(relabeled.startedAtMs, 61000, "changing the label starts a new segment")
assert.equal(model.closedSegment(model.pause(state, 5000), 9000), null, "paused stopwatches have no open segment")
assert.equal(model.closedSegment(state, 1500), null, "sub-second blips are not recorded")

let quick = model.startWithLabel(model.stoppedState(0, "Old"), "Client A", 5000, 9000)
assert.equal(quick.status, model.StatusRunning, "choosing a label at zero starts the clock")
assert.equal(quick.label, "Client A")
assert.equal(model.elapsedSeconds(quick, 9000), 4, "the time spent choosing the label counts")
assert.equal(model.startWithLabel(model.stoppedState(0), "A", 99999, 9000).startedAtMs, 9000, "a future start is clamped to now")
assert.equal(model.startWithLabel(model.stoppedState(0), "A", undefined, 9000).startedAtMs, 9000)

// ---- History and label suggestions.
let history = model.emptyHistory()
history = model.appendSegment(history, { label: "Client A – PPC audit", startMs: 0, endMs: 60000 }, 60000)
history = model.appendSegment(history, { label: "", startMs: 70000, endMs: 80000 }, 80000)
history = model.appendSegment(history, { label: "Brand X – listings", startMs: 90000, endMs: 99000 }, 99000)
history = model.appendSegment(history, { label: "client a – ppc AUDIT", startMs: 100000, endMs: 110000 }, 110000)
history = model.appendSegment(history, { label: "Clinique store", startMs: 120000, endMs: 130000 }, 130000)

const known = Array.from(model.knownLabels(history, ""))
assert.deepEqual(known, ["Clinique store", "client a – ppc AUDIT", "Brand X – listings"],
                 "every label once, newest first, in its newest spelling, without blanks")
assert.deepEqual(Array.from(model.knownLabels(history, "New one")).slice(0, 2), ["New one", "Clinique store"],
                 "the current label is offered first")

const labels = ["Clinique store", "Client A – PPC audit", "Brand X – listings", "Topclient"]
assert.deepEqual(Array.from(model.suggestLabels(labels, "")), labels, "an empty query lists everything")
assert.deepEqual(Array.from(model.suggestLabels(labels, "cli")),
                 ["Clinique store", "Client A – PPC audit", "Topclient"],
                 "labels starting with the text come before ones that merely contain it")
assert.deepEqual(Array.from(model.suggestLabels(labels, "list")), ["Brand X – listings"],
                 "matches the start of a later word")
assert.deepEqual(Array.from(model.suggestLabels(labels, "PPC")), ["Client A – PPC audit"], "case does not matter")
assert.deepEqual(Array.from(model.suggestLabels(labels, "a (")), [], "special characters are matched literally")

assert.equal(model.canonicalLabel(labels, "  brand x –   LISTINGS "), "Brand X – listings",
             "typing a known label in another case keeps its earlier spelling")
assert.equal(model.canonicalLabel(labels, "New client"), "New client")

const pruned = model.appendSegment(history, null, 100 * model.DayMs)
assert.equal(pruned.sessions.length, 0, "history older than 90 days is dropped")
assert.equal(model.sanitizeHistory({ version: 1, sessions: [{ startMs: 5, endMs: 1 }, { startMs: 1, endMs: 5 }] })
  .sessions.length, 1, "broken history entries are dropped")
assert.equal(model.sanitizeHistory("nonsense").sessions.length, 0)

// ---- Formatting.
assert.equal(model.formatElapsed(0), "00:00")
assert.equal(model.formatElapsed(65), "01:05")
assert.equal(model.formatElapsed(3600), "1:00:00")
assert.equal(model.formatElapsed(37815), "10:30:15")
assert.equal(model.formatHundredths(1234), ".23")

console.log("stopwatch model tests passed")
