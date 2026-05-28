# @infinity-msfs/rescript-efb-mirror

ReScript React library for building an EFB that runs **both** in-sim
(inside MSFS) and as a browser/iPad mirror, sharing all component code.

See [DESIGN.md](./DESIGN.md) for the protocol + architecture spec.

## Install

```bash
pnpm add @infinity-msfs/rescript-efb-mirror
# Add to your rescript.json `bs-dependencies`:
#   "@infinity-msfs/rescript-efb-mirror"
```

## Usage

### Mirror build (browser / iPad)

```rescript
@react.component
let App = () =>
  switch EfbMirror.Pairing.readStored() {
  | Some({url, token}) =>
    <EfbMirror.Provider mode={Mirror({url, token})}>
      <YourEfb />
    </EfbMirror.Provider>
  | None =>
    <EfbMirror.Pairing onPaired={_ => Window.location.reload()} />
  }
```

### In-sim build

```rescript
@react.component
let App = () =>
  <EfbMirror.Provider mode=InSim>
    <SimBridge />   // your sim-var publishers, see below
    <YourEfb />
  </EfbMirror.Provider>
```

### EFB component code (shared)

```rescript
@react.component
let Altimeter = () => {
  let alt = EfbMirror.Hooks.useSimVar(~key="ALT_FT")
  let (units, setUnits) = EfbMirror.Hooks.useUiState(
    ~key="alt.units",
    ~default=JSON.Encode.string("ft"),
  )
  ...
}
```

Identical between the two builds.

### Bridging sim vars (in-sim only)

The library is intentionally decoupled from `rescript-msfs`. To publish
sim vars, write a tiny component per var:

```rescript
@react.component
let PublishAlt = () => {
  let (alt, _) = RescriptMsfs.Hooks.useSimVar("L:T38_ALT_FT", "feet", ())
  EfbMirror.Hooks.usePublishSimVar(~key="ALT_FT", ~value=JSON.Encode.float(alt))
  React.null
}
```

Mount these inside the `<EfbMirror.Provider mode=InSim>` tree. They write
to the local store *and* push the value to the manager so mirror clients
see it.

## Build

```bash
pnpm install
pnpm build
```

Produces `lib/es6/*.res.mjs`. Bundle for the mirror SPA with Vite (or
your bundler of choice) and ship the dist into
`crates/efb-server/static/` so the manager serves it.
