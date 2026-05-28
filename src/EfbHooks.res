// Public hooks. Every hook reads from the local store; the WS client
// (in Mirror mode) or a `SimPublisher` component (in InSim mode) is what
// keeps the store hydrated.
//
// Identical hook signatures and behaviour in both modes — EFB component
// code is mode-agnostic.

let useStoreValue = (~channel: Types.channel, ~key: string): option<JSON.t> => {
  let ctx = EfbProvider.useCtx()
  let store = ctx.store
  let subscribe = (notify: unit => unit) => EfbStore.subscribe(store, channel, key, notify)
  let getSnapshot = () => EfbStore.read(store, channel, key)
  React.useSyncExternalStore(~subscribe, ~getSnapshot)
}

@doc("
Read a sim-channel value by key. The value is whatever the publisher wrote
(typically a number). Returns `None` until the first value lands.

  let alt = EfbHooks.useSimVar(~key=\"ALT_FT\")
")
let useSimVar = (~key: string): option<JSON.t> => useStoreValue(~channel=#sim, ~key)

@doc("
Read + write a UI-state key. The setter sends a `ui` frame over the WS;
the local store updates on the manager's rebroadcast, so all clients
(including the originator) commit on the same authoritative ordering.

  let (page, setPage) = EfbHooks.useUiState(~key=\"page\", ~default=JSON.Encode.string(\"home\"))
")
let useUiState = (~key: string, ~default: JSON.t): (JSON.t, JSON.t => unit) => {
  let ctx = EfbProvider.useCtx()
  let stored = useStoreValue(~channel=#ui, ~key)
  let value = stored->Option.getOr(default)
  let setter = (v: JSON.t) =>
    switch ctx.ws {
    | Some(ws) => EfbWs.sendUi(ws, key, v)
    | None =>
      // InSim mode without a WS hookup: write locally so the EFB still
      // works standalone. When the manager WS exists, the SimPublisher
      // glue is responsible for sending writes.
      let d = Dict.make()
      Dict.set(d, key, v)
      EfbStore.applyDelta(ctx.store, #ui, d)
    }
  (value, setter)
}

@doc("
Fire a one-shot `cmd` event. No return — the originator already knows it
sent. Other clients receive it via `useCmdSubscription`.

  let refresh = EfbHooks.useCmd(~name=\"refresh.charts\")
  <button onClick={_ => refresh(JSON.Encode.string(\"KSFO\"))}>...</button>
")
let useCmd = (~name: string): (JSON.t => unit) => {
  let ctx = EfbProvider.useCtx()
  (data: JSON.t) =>
    switch ctx.ws {
    | Some(ws) => EfbWs.sendCmd(ws, name, data)
    | None => Console.warn2("efb-mirror: cmd dropped (no WS)", name)
    }
}

@doc("
Subscribe to incoming `cmd` events with the given name. The handler is
called with the JSON payload. Multiple components can subscribe to the
same name — all receive every fire.
")
let useCmdSubscription = (~name: string, handler: JSON.t => unit): unit => {
  let ctx = EfbProvider.useCtx()
  React.useEffect2(() => {
    switch ctx.ws {
    | Some(ws) => Some(EfbWs.onCmd(ws, name, (_, data) => handler(data)))
    | None => None
    }
  }, (name, ctx.ws))
}

@doc("
Current WS connection state. Returns `#InSim` when the provider is in
InSim mode and no WS is open.
")
let useConnection = (): Types.connection => {
  let ctx = EfbProvider.useCtx()
  let getSnapshot = () =>
    switch ctx.ws {
    | Some(ws) => EfbWs.getConnection(ws)
    | None => #InSim
    }
  let subscribe = (notify: unit => unit) =>
    switch ctx.ws {
    | Some(ws) => EfbWs.onConnectionChange(ws, notify)
    | None => () => ()
    }
  React.useSyncExternalStore(~subscribe, ~getSnapshot)
}

@doc("
Publisher hook for in-sim builds. Pair the value you read from your sim
hook (e.g. rescript-msfs) with the wire key it should be published as.
On every value change, writes the value to the local store and (if a WS
is open) sends a `sim` frame so mirror clients see it too.

  let (alt, _) = RescriptMsfs.Hooks.useSimVar(\"L:T38_ALT_FT\", \"feet\", ())
  EfbHooks.usePublishSimVar(~key=\"ALT_FT\", ~value=JSON.Encode.float(alt))
")
let usePublishSimVar = (~key: string, ~value: JSON.t): unit => {
  let ctx = EfbProvider.useCtx()
  React.useEffect2(() => {
    // Mirror into local store so other components in this build see the
    // same value path as in mirror mode (cleaner uniformity).
    let d = Dict.make()
    Dict.set(d, key, value)
    EfbStore.applyDelta(ctx.store, #sim, d)
    // Push to manager so remote mirrors see it.
    switch ctx.ws {
    | Some(ws) => EfbWs.sendSim(ws, key, value)
    | None => ()
    }
    None
  }, (key, value))
}
