// Minimal WebSocket bindings — just what EfbWs needs. Browsers and the MSFS
// in-game WebView both implement the standard WHATWG WebSocket API.

type t

module MessageEvent = {
  type t
  @get external data: t => 'a = "data"
}

type closeEvent
type errorEvent
type openEvent

// Scoped on `window` so the emitted `new window.WebSocket(url)` doesn't
// collide with the consumer's `import * as WebSocket from
// "./WebSocket.res.mjs"` namespace binding. Two reasons we can't just use
// the bare name or `globalThis`:
//
//   - Bare `new WebSocket(url)` resolves to the *imported namespace
//     object* under module bundlers (Object is not a constructor).
//   - `globalThis` works in modern browsers but not in MSFS's older
//     Coherent runtime, which throws `Can't find variable: globalThis`.
//
// `window` is universal across browser, iPad Safari, and Coherent.
@new @scope("window") external make: string => t = "WebSocket"

@send external sendText: (t, string) => unit = "send"
@send external close: t => unit = "close"

// `@send` can't inject the event-name string addEventListener needs, so the
// listener wrappers go through a tiny %raw shim instead.
%%raw(`
function _efb_addOpen(ws, cb) { ws.addEventListener("open", cb); }
function _efb_addClose(ws, cb) { ws.addEventListener("close", cb); }
function _efb_addError(ws, cb) { ws.addEventListener("error", cb); }
function _efb_addMessage(ws, cb) { ws.addEventListener("message", cb); }
`)

let addOpenListener: (t, openEvent => unit) => unit = %raw(`_efb_addOpen`)
let addCloseListener: (t, closeEvent => unit) => unit = %raw(`_efb_addClose`)
let addErrorListener: (t, errorEvent => unit) => unit = %raw(`_efb_addError`)
let addMessageListener: (t, MessageEvent.t => unit) => unit = %raw(`_efb_addMessage`)
