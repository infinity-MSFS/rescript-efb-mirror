// Shared types for the EFB mirror library.
//
// Frame shapes match `rescript-efb-mirror/DESIGN.md` 1-for-1. Keep this file
// and `crates/efb-server/src/protocol.rs` in lock-step — they're the wire
// contract.

/// Channel identifier. Used internally by the store to namespace key
/// subscriptions. The wire protocol carries each channel in its own frame
/// type (`sim` / `ui` / `cmd`), so this only surfaces in hook signatures.
type channel = [#sim | #ui]

/// Connection state surfaced via `useConnection`. EFB components can read
/// this to dim controls / show a banner when not paired.
type connection = [#Connecting | #Open | #Closed | #InSim]

/// Provider mode. InSim renders nothing extra (the EFB app is responsible
/// for mounting any sim → store publishers, see `SimPublisher`). Mirror
/// opens a WS to the given URL with the given pairing token.
type mode =
  | InSim
  | Mirror({url: string, token: string})

/// One published sim var the in-sim build wants mirrored to remote clients.
/// `name` and `unit` are passed to `rescript-msfs` (or whatever the user is
/// using to read sim state); `key` is the wire-side key the value is
/// published under on the `sim` channel.
type publishedSimVar = {
  key: string,
  name: string,
  unit: string,
}
