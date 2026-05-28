// React context provider for the EFB mirror library. Owns the store and (in
// Mirror mode) the WS client. EFB components below this consume both via the
// hooks in EfbHooks.

type ctx = {
  store: EfbStore.t,
  ws: option<EfbWs.t>,
  mode: Types.mode,
}

let context = React.createContext({
  store: EfbStore.make(),
  ws: None,
  mode: InSim,
})

module Provider = {
  let make = React.Context.provider(context)
}

@react.component
let make = (~mode: Types.mode, ~children: React.element) => {
  // The store is created once per Provider instance and kept stable across
  // renders. WS lifecycle is mode-dependent.
  let ctxRef = React.useRef(None)

  let ctx = switch ctxRef.current {
  | Some(c) => c
  | None =>
    let store = EfbStore.make()
    let ws = switch mode {
    | InSim => None
    | Mirror({url, token}) => Some(EfbWs.make(~store, ~url, ~token))
    }
    let c = {store, ws, mode}
    ctxRef.current = Some(c)
    c
  }

  React.useEffect0(() => {
    // 20 s ping interval matches the manager's 60 s idle close.
    let interval = switch ctx.ws {
    | Some(ws) =>
      Some(setInterval(() => EfbWs.sendPing(ws), 20_000))
    | None => None
    }
    Some(
      () => {
        switch interval {
        | Some(id) => clearInterval(id)
        | None => ()
        }
        switch ctx.ws {
        | Some(ws) => EfbWs.close(ws)
        | None => ()
        }
      },
    )
  })

  <Provider value=ctx> children </Provider>
}

let useCtx = () => React.useContext(context)
