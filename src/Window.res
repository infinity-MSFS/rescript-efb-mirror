// Minimal `window` bindings used by EfbPairing. `@rescript/core` doesn't
// ship DOM bindings out of the box; rather than pulling in Webapi we
// expose only the surface we use.

type location = {
  protocol: string,
  host: string,
  href: string,
}

@val external location: location = "window.location"
@val external localStorage: dict<string> = "window.localStorage"
