optimize: add a option to controls whether debugPrintRoute executes
**Is your feature request related to a problem? Please describe.**

-  When the server is running, it  will print a lot of logs of the routes and i wish I could control its printing

**Describe the solution you'd like**

- add a option

### Additional contract requirements

- Add a public function `WithDisablePrintRoute(b bool)` in package `pkg/app/server` that returns a `config.Option` (from `github.com/cloudwego/hertz/pkg/common/config`). Applying it sets the public `DisablePrintRoute` field of `config.Options` to `b`.
- When `DisablePrintRoute` is true, registering a route must not print the route information. When it is false (the default), registering a route prints the route information.
