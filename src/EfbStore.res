// In-memory key/value store mirroring the manager's authoritative state.
//
// Two flat dicts (sim, ui) plus per-key subscriber lists. Designed for
// `React.useSyncExternalStore` so consumers only re-render when their
// specific key changes — a fast-rolling `ALT_FT` doesn't wake up
// components that only read `IAS_KT`.
//
// The store is also the local cache for in-sim mode: a `SimPublisher`
// that bridges MSFS hooks writes into the same dict the rest of the
// EFB reads from, so component code is identical in both modes.

type listener = unit => unit

type channelDict = {
  values: dict<JSON.t>,
  // Map<key, array<listener>>. Allocated lazily per key. Listeners are
  // notified when their key's value (by structural equality on JSON) changes.
  subs: dict<array<listener>>,
}

type t = {
  sim: channelDict,
  ui: channelDict,
  // Wildcard listeners fired on any change in a channel. The UI affordance
  // for connection state uses this so it can render a generic "x updates
  // since connect" indicator without subscribing to every key.
  mutable wildcardSim: array<listener>,
  mutable wildcardUi: array<listener>,
}

let make = (): t => {
  sim: {values: Dict.make(), subs: Dict.make()},
  ui: {values: Dict.make(), subs: Dict.make()},
  wildcardSim: [],
  wildcardUi: [],
}

@inline
let channelOf = (store, ch: Types.channel) =>
  switch ch {
  | #sim => store.sim
  | #ui => store.ui
  }

let read = (store: t, ch: Types.channel, key: string): option<JSON.t> =>
  (channelOf(store, ch)).values->Dict.get(key)

let notify = (subs: array<listener>) => {
  let len = Array.length(subs)
  for i in 0 to len - 1 {
    let l = subs->Array.getUnsafe(i)
    l()
  }
}

let subscribe = (store: t, ch: Types.channel, key: string, l: listener): (unit => unit) => {
  let d = channelOf(store, ch)
  let arr = switch d.subs->Dict.get(key) {
  | Some(a) => a
  | None =>
    let a = []
    d.subs->Dict.set(key, a)
    a
  }
  arr->Array.push(l)
  () => {
    let idx = arr->Array.indexOf(l)
    if idx >= 0 {
      let _ = arr->Array.splice(~start=idx, ~remove=1, ~insert=[])
    }
  }
}

let subscribeChannel = (store: t, ch: Types.channel, l: listener): (unit => unit) => {
  switch ch {
  | #sim =>
    store.wildcardSim->Array.push(l)
    () => {
      let idx = store.wildcardSim->Array.indexOf(l)
      if idx >= 0 {
        store.wildcardSim = store.wildcardSim->Array.filterWithIndex((_, i) => i !== idx)
      }
    }
  | #ui =>
    store.wildcardUi->Array.push(l)
    () => {
      let idx = store.wildcardUi->Array.indexOf(l)
      if idx >= 0 {
        store.wildcardUi = store.wildcardUi->Array.filterWithIndex((_, i) => i !== idx)
      }
    }
  }
}

@inline
let jsonEq = (a: JSON.t, b: JSON.t): bool =>
  // Structural equality via JSON serialization. Slower than custom recursion
  // but bulletproof for arbitrary nested values; sim deltas are flat scalars
  // and ui state is shallow, so the cost is trivial in practice.
  JSON.stringify(a) === JSON.stringify(b)

/// Apply a delta from the wire. `data` is a Dict<key, value>; a value of
/// `JSON.Null` deletes the key. Notifies per-key subscribers of changed
/// keys only; wildcard subscribers are notified once if anything changed.
let applyDelta = (store: t, ch: Types.channel, data: dict<JSON.t>) => {
  let d = channelOf(store, ch)
  let changedAny = ref(false)
  data
  ->Dict.toArray
  ->Array.forEach(((k, v)) => {
    let isNull = JSON.Classify.classify(v) === JSON.Classify.Null
    let prev = d.values->Dict.get(k)
    let changed = switch (prev, isNull) {
    | (None, true) => false
    | (None, false) => true
    | (Some(p), false) => !jsonEq(p, v)
    | (Some(_), true) => true
    }
    if changed {
      if isNull {
        Dict.delete(d.values, k)
      } else {
        Dict.set(d.values, k, v)
      }
      switch d.subs->Dict.get(k) {
      | Some(subs) => notify(subs)
      | None => ()
      }
      changedAny := true
    }
  })
  if changedAny.contents {
    let wc = switch ch {
    | #sim => store.wildcardSim
    | #ui => store.wildcardUi
    }
    notify(wc)
  }
}

/// Replace the entire snapshot (used on connect and on resync). Notifies
/// everything that changed (which is, on first connect, every key).
let applySnapshot = (
  store: t,
  ~sim: dict<JSON.t>,
  ~ui: dict<JSON.t>,
) => {
  // Reuse applyDelta to get per-key change detection + notifications. For
  // initial connect this means firing a notification per known key, which
  // is exactly what we want — useSyncExternalStore consumers re-render
  // off their first subscribe regardless.
  // Add deletions for keys we have locally that the snapshot dropped.
  let mergedSim = Dict.make()
  store.sim.values
  ->Dict.keysToArray
  ->Array.forEach(k =>
    if !(sim->Dict.get(k)->Option.isSome) {
      Dict.set(mergedSim, k, JSON.Null)
    }
  )
  sim->Dict.toArray->Array.forEach(((k, v)) => Dict.set(mergedSim, k, v))
  applyDelta(store, #sim, mergedSim)

  let mergedUi = Dict.make()
  store.ui.values
  ->Dict.keysToArray
  ->Array.forEach(k =>
    if !(ui->Dict.get(k)->Option.isSome) {
      Dict.set(mergedUi, k, JSON.Null)
    }
  )
  ui->Dict.toArray->Array.forEach(((k, v)) => Dict.set(mergedUi, k, v))
  applyDelta(store, #ui, mergedUi)
}
