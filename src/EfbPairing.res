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

/// Tablet self-forget. Wipes the stored credentials and reloads the page so
/// the consumer's root component re-runs `readStored` (gets `None`) and
/// renders the pairing screen again. Useful for testing the pair flow
/// repeatedly without having to use the manager's "Forget all" hammer.
let unpairAndReload: unit => unit = %raw(`
  function() {
    try { window.localStorage.removeItem("efb-mirror-creds"); } catch (e) {}
    window.location.reload();
  }
`)

/// Default WS URL derived from the page's own host — the mirror SPA is
/// served by the same manager process on the same port, so `wss?://host/ws`
/// is the right target without making the user type it.
let defaultUrlFromLocation = (): string => {
  let proto = Window.location.protocol === "https:" ? "wss:" : "ws:"
  let host = Window.location.host
  `${proto}//${host}/ws`
}

let _parseQueryCreds: string => option<creds> = %raw(`
  function(search) {
    try {
      var p = new URLSearchParams(search);
      var u = p.get("url");
      var t = p.get("token");
      if (u && t) { return { url: u, token: t }; }
      return undefined;
    } catch (e) {
      return undefined;
    }
  }
`)

let _parseQueryCode: string => option<string> = %raw(`
  function(search) {
    try {
      var p = new URLSearchParams(search);
      var c = p.get("code");
      if (c) { return c.toUpperCase(); }
      return undefined;
    } catch (e) {
      return undefined;
    }
  }
`)

/// Try to read `?url=&token=` from the current location. The manager's
/// pairing-QR payload embeds both so a tablet scan one-shots the pair flow:
/// scan → open URL → mirror loads → auto-pair → strip query so the token
/// isn't visible in the address bar afterwards.
let readQueryCreds = (): option<creds> => {
  let search = Window.location.search
  if search === "" {
    None
  } else {
    _parseQueryCreds(search)
  }
}

/// Try to read `?code=ABCDE` from the current location — the QR payload
/// when the manager issues a short pairing code instead of the long token.
let readQueryCode = (): option<string> => {
  let search = Window.location.search
  if search === "" {
    None
  } else {
    _parseQueryCode(search)
  }
}

/// Exchange a short pairing code for the long WS token via
/// `GET /pair?code=XXXXX` on the same origin (the manager serves both the
/// SPA and the WS). Returns the creds ready for storage + WS connect.
///
/// Implemented as a single %raw fetch — keeps the lib free of any HTTP
/// abstraction layer and works under whatever runtime the mirror is hosted
/// in (browser, iPad Safari, MSFS WebView).
let redeemPairingCode: string => promise<result<creds, string>> = %raw(`
  async function(code) {
    var url = "/pair?code=" + encodeURIComponent(code);
    var res;
    try {
      res = await fetch(url, { method: "GET", credentials: "same-origin" });
    } catch (e) {
      return { TAG: "Error", _0: "Network error reaching manager" };
    }
    if (!res.ok) {
      var msg;
      if (res.status === 404) msg = "Unknown or already-used code";
      else if (res.status === 410) msg = "Code expired — generate a new one";
      else msg = "Pair failed (HTTP " + res.status + ")";
      return { TAG: "Error", _0: msg };
    }
    var body;
    try {
      body = await res.json();
    } catch (e) {
      return { TAG: "Error", _0: "Malformed pair response" };
    }
    if (!body || typeof body.token !== "string" || body.token === "") {
      return { TAG: "Error", _0: "Manager returned no token" };
    }
    var proto = window.location.protocol === "https:" ? "wss:" : "ws:";
    var host = window.location.host;
    var wsUrl = proto + "//" + host + "/ws";
    return { TAG: "Ok", _0: { url: wsUrl, token: body.token } };
  }
`)

/// Remove `url=&token=` from the address bar after a successful auto-pair.
/// Uses replaceState so the back button doesn't bring the query back.
let stripQuery: unit => unit = %raw(`
  function() {
    var path = window.location.pathname || "/";
    window.history.replaceState(null, "", path);
  }
`)

@react.component
let make = (~onPaired: creds => unit) => {
  let (code, setCode) = React.useState(() => "")
  let (error, setError) = React.useState(() => None)
  let (busy, setBusy) = React.useState(() => false)

  let submit = async c => {
    setBusy(_ => true)
    setError(_ => None)
    let result = await redeemPairingCode(c)
    setBusy(_ => false)
    switch result {
    | Ok(creds) =>
      writeStored(creds)
      onPaired(creds)
    | Error(msg) => setError(_ => Some(msg))
    }
  }

  let onSubmit = ev => {
    ReactEvent.Form.preventDefault(ev)
    let c = String.trim(code)->String.toUpperCase
    if c === "" {
      setError(_ => Some("Enter the 5-character code shown in the manager"))
    } else {
      submit(c)->ignore
    }
  }

  <form onSubmit className="efb-mirror-pairing">
    <h1> {React.string("Pair this device")} </h1>
    <p>
      {React.string(
        "Open the Infinity Manager on the sim host. Under Settings → EFB tablet sharing, hit \"Generate code\" and type the 5 characters below.",
      )}
    </p>
    <label>
      {React.string("Pairing code")}
      <input
        type_="text"
        value=code
        onChange={ev => setCode(_ => (ev->ReactEvent.Form.target)["value"])}
        autoFocus=true
        maxLength=5
        autoComplete="off"
        autoCapitalize="characters"
        spellCheck=false
      />
    </label>
    {switch error {
    | Some(msg) => <p className="efb-mirror-pairing-error"> {React.string(msg)} </p>
    | None => React.null
    }}
    <button type_="submit" disabled=busy>
      {React.string(busy ? "Pairing…" : "Pair")}
    </button>
  </form>
}
