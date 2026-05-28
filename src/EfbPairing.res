// One-time pairing screen for the mirror SPA. The user lands here on first
// visit, pastes the token shown in the manager UI, and the credentials are
// stashed in localStorage so subsequent loads skip straight to the EFB.
//
// The lib doesn't render the *EFB* — that's the consumer's job. We render
// the chrome and call back with the validated `url` + `token`.

let storageKey = "efb-mirror-creds"

type creds = {url: string, token: string}

let readStored = (): option<creds> => {
  let raw = try Some(Dict.getUnsafe(Window.localStorage, storageKey)) catch {
  | _ => None
  }
  switch raw {
  | Some(s) when s !== "" =>
    let parsed = try JSON.parseExn(s) catch {
    | _ => JSON.Null
    }
    switch JSON.Decode.object(parsed) {
    | Some(o) =>
      let url = o->Dict.get("url")->Option.flatMap(JSON.Decode.string)->Option.getOr("")
      let token = o->Dict.get("token")->Option.flatMap(JSON.Decode.string)->Option.getOr("")
      if url !== "" && token !== "" {
        Some({url, token})
      } else {
        None
      }
    | None => None
    }
  | _ => None
  }
}

let writeStored = (c: creds) => {
  let d = Dict.make()
  Dict.set(d, "url", JSON.Encode.string(c.url))
  Dict.set(d, "token", JSON.Encode.string(c.token))
  Window.localStorage->Dict.set(storageKey, JSON.stringify(JSON.Encode.object(d)))
}

let clearStored = () => {
  try {
    Window.localStorage->Dict.set(storageKey, "")
  } catch {
  | _ => ()
  }
}

/// Default WS URL derived from the page's own host — the mirror SPA is
/// served by the same manager process on the same port, so `wss?://host/ws`
/// is the right target without making the user type it.
let defaultUrlFromLocation = (): string => {
  let proto = Window.location.protocol === "https:" ? "wss:" : "ws:"
  let host = Window.location.host
  `${proto}//${host}/ws`
}

@react.component
let make = (~onPaired: creds => unit) => {
  let (token, setToken) = React.useState(() => "")
  let (url, setUrl) = React.useState(() => defaultUrlFromLocation())
  let (error, setError) = React.useState(() => None)

  let onSubmit = ev => {
    ReactEvent.Form.preventDefault(ev)
    let t = String.trim(token)
    let u = String.trim(url)
    if t === "" {
      setError(_ => Some("Pairing token is required"))
    } else if u === "" {
      setError(_ => Some("WS URL is required"))
    } else {
      let creds = {url: u, token: t}
      writeStored(creds)
      onPaired(creds)
    }
  }

  <form onSubmit className="efb-mirror-pairing">
    <h1> {React.string("Pair this device")} </h1>
    <p>
      {React.string(
        "Open the Infinity Manager on the sim host. Under Settings → EFB mirror, copy the pairing token below.",
      )}
    </p>
    <label>
      {React.string("WebSocket URL")}
      <input
        type_="text"
        value=url
        onChange={ev => setUrl(_ => (ev->ReactEvent.Form.target)["value"])}
      />
    </label>
    <label>
      {React.string("Pairing token")}
      <input
        type_="text"
        value=token
        onChange={ev => setToken(_ => (ev->ReactEvent.Form.target)["value"])}
        autoFocus=true
      />
    </label>
    {switch error {
    | Some(msg) => <p className="efb-mirror-pairing-error"> {React.string(msg)} </p>
    | None => React.null
    }}
    <button type_="submit"> {React.string("Pair")} </button>
  </form>
}
