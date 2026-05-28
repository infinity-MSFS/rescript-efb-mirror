// Tiny WebSocket client. Connects, parses incoming JSON frames into store
// mutations, exposes a `send` for the hooks layer. Auto-reconnects with
// exponential backoff (capped at 30 s).
//
// One client per Provider instance — kept alive in a ref so React StrictMode
// double-mounting in dev doesn't churn the connection.

type cmdHandler = (string, JSON.t) => unit

type t = {
  store: EfbStore.t,
  mutable socket: option<WebSocket.t>,
  mutable closed: bool,
  mutable retry: int,
  mutable connection: Types.connection,
  mutable connectionListeners: array<unit => unit>,
  mutable cmdListeners: dict<array<cmdHandler>>,
  url: string,
  token: string,
}

let onConnectionChange = (t: t, l: unit => unit): (unit => unit) => {
  t.connectionListeners->Array.push(l)
  () => {
    t.connectionListeners =
      t.connectionListeners->Array.filter(x => !Object.is(x->Obj.magic, l->Obj.magic))
  }
}

let getConnection = (t: t) => t.connection

let setConnection = (t: t, c: Types.connection) => {
  t.connection = c
  EfbStore.notify(t.connectionListeners)
}

let onCmd = (t: t, name: string, h: cmdHandler): (unit => unit) => {
  let arr = switch t.cmdListeners->Dict.get(name) {
  | Some(a) => a
  | None =>
    let a = []
    t.cmdListeners->Dict.set(name, a)
    a
  }
  arr->Array.push(h)
  () => {
    let idx = arr->Array.indexOf(h)
    if idx >= 0 {
      let _ = arr->Array.splice(~start=idx, ~remove=1, ~insert=[])
    }
  }
}

// --- frame parsing ----------------------------------------------------------

let dictOf = (j: JSON.t): dict<JSON.t> =>
  switch JSON.Decode.object(j) {
  | Some(d) => d
  | None => Dict.make()
  }

let handleFrame = (t: t, raw: string) => {
  let parsed = try JSON.parseExn(raw) catch {
  | _ => JSON.Null
  }
  let obj = switch JSON.Decode.object(parsed) {
  | Some(o) => o
  | None => Dict.make()
  }
  let kind = obj->Dict.get("t")->Option.flatMap(JSON.Decode.string)->Option.getOr("")
  switch kind {
  | "snapshot" =>
    let sim = obj->Dict.get("sim")->Option.map(dictOf)->Option.getOr(Dict.make())
    let ui = obj->Dict.get("ui")->Option.map(dictOf)->Option.getOr(Dict.make())
    EfbStore.applySnapshot(t.store, ~sim, ~ui)
  | "sim" =>
    let data = obj->Dict.get("data")->Option.map(dictOf)->Option.getOr(Dict.make())
    EfbStore.applyDelta(t.store, #sim, data)
  | "ui" =>
    let data = obj->Dict.get("data")->Option.map(dictOf)->Option.getOr(Dict.make())
    EfbStore.applyDelta(t.store, #ui, data)
  | "cmd" =>
    let name = obj->Dict.get("name")->Option.flatMap(JSON.Decode.string)->Option.getOr("")
    let data = obj->Dict.get("data")->Option.getOr(JSON.Null)
    if name !== "" {
      switch t.cmdListeners->Dict.get(name) {
      | Some(hs) => hs->Array.forEach(h => h(name, data))
      | None => ()
      }
    }
  | "pong" => ()
  | _ => Console.warn2("efb-mirror: unknown frame type", kind)
  }
}

// --- WebSocket lifecycle ----------------------------------------------------

let rec connect = (t: t) => {
  if t.closed {
    ()
  } else {
    setConnection(t, #Connecting)
    let url = `${t.url}?token=${t.token}`
    let ws = WebSocket.make(url)
    t.socket = Some(ws)

    ws->WebSocket.addOpenListener(_ => {
      t.retry = 0
      setConnection(t, #Open)
    })
    ws->WebSocket.addMessageListener(ev => {
      let raw = ev->WebSocket.MessageEvent.data
      switch JSON.Classify.classify(raw->Obj.magic) {
      | JSON.Classify.String(s) => handleFrame(t, s)
      | _ => ()
      }
    })
    ws->WebSocket.addCloseListener(_ => {
      t.socket = None
      setConnection(t, #Closed)
      if !t.closed {
        let delay = Math.min(30000.0, 500.0 *. Math.pow(2.0, ~exp=Int.toFloat(t.retry)))
        t.retry = t.retry + 1
        let _ = setTimeout(() => connect(t), Float.toInt(delay))
      }
    })
    ws->WebSocket.addErrorListener(_ => {
      // Close handler will run next; nothing to do here.
      ()
    })
  }
}

let make = (~store: EfbStore.t, ~url: string, ~token: string): t => {
  let t = {
    store,
    socket: None,
    closed: false,
    retry: 0,
    connection: #Closed,
    connectionListeners: [],
    cmdListeners: Dict.make(),
    url,
    token,
  }
  connect(t)
  t
}

let close = (t: t) => {
  t.closed = true
  switch t.socket {
  | Some(ws) =>
    ws->WebSocket.close
    t.socket = None
  | None => ()
  }
  setConnection(t, #Closed)
}

let sendRaw = (t: t, payload: string) =>
  switch t.socket {
  | Some(ws) when t.connection === #Open => ws->WebSocket.sendText(payload)
  | _ => Console.warn("efb-mirror: send before open; dropped")
  }

let sendUi = (t: t, key: string, value: JSON.t) => {
  let data = Dict.make()
  Dict.set(data, key, value)
  let frame = Dict.make()
  Dict.set(frame, "t", JSON.Encode.string("ui"))
  Dict.set(frame, "data", JSON.Encode.object(data))
  sendRaw(t, JSON.stringify(JSON.Encode.object(frame)))
}

let sendSim = (t: t, key: string, value: JSON.t) => {
  let data = Dict.make()
  Dict.set(data, key, value)
  let frame = Dict.make()
  Dict.set(frame, "t", JSON.Encode.string("sim"))
  Dict.set(frame, "data", JSON.Encode.object(data))
  sendRaw(t, JSON.stringify(JSON.Encode.object(frame)))
}

let sendCmd = (t: t, name: string, data: JSON.t) => {
  let frame = Dict.make()
  Dict.set(frame, "t", JSON.Encode.string("cmd"))
  Dict.set(frame, "name", JSON.Encode.string(name))
  Dict.set(frame, "data", data)
  sendRaw(t, JSON.stringify(JSON.Encode.object(frame)))
}

let sendPing = (t: t) => {
  let frame = Dict.make()
  Dict.set(frame, "t", JSON.Encode.string("ping"))
  sendRaw(t, JSON.stringify(JSON.Encode.object(frame)))
}
