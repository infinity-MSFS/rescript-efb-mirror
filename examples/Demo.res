// Minimal demo showing the same component working in both modes.

module SharedEfb = {
  @react.component
  let make = () => {
    let alt = EfbMirror.Hooks.useSimVar(~key="ALT_FT")
    let (page, setPage) = EfbMirror.Hooks.useUiState(
      ~key="page",
      ~default=JSON.Encode.string("home"),
    )
    let conn = EfbMirror.Hooks.useConnection()

    let altText = switch alt {
    | Some(v) => JSON.stringify(v)
    | None => "—"
    }

    <div>
      <header>
        <span> {React.string(`Connection: ${(conn :> string)}`)} </span>
        <span> {React.string(` · ALT ${altText} ft`)} </span>
      </header>
      <nav>
        {["home", "charts", "perf"]
        ->Array.map(p => {
          let active = JSON.Decode.string(page)->Option.getOr("") === p
          <button
            key=p
            onClick={_ => setPage(JSON.Encode.string(p))}
            className={active ? "active" : ""}>
            {React.string(p)}
          </button>
        })
        ->React.array}
      </nav>
    </div>
  }
}

module MirrorEntry = {
  @react.component
  let make = () =>
    switch EfbMirror.Pairing.readStored() {
    | Some({url, token}) =>
      <EfbMirror.Provider mode={Mirror({url, token})}>
        <SharedEfb />
      </EfbMirror.Provider>
    | None =>
      <EfbMirror.Pairing
        onPaired={_ => {
          // Round-trip via reload so the Provider mounts fresh with the
          // new creds — keeps the lifecycle path identical to "land on
          // already-paired device".
          Window.location.href->ignore
          %raw(`window.location.reload()`)
        }}
      />
    }
}

module InSimEntry = {
  @react.component
  let make = () =>
    <EfbMirror.Provider mode=InSim>
      // In a real in-sim build the EFB app mounts its own SimPublisher
      // children here that bridge MSFS values into the store. See README.
      <SharedEfb />
    </EfbMirror.Provider>
}
