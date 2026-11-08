Provide a way to do local development (plugins should be informed about this to change behavior)
Currently, the `xsrf` plugin sets a safe cookie with the `Secure` option, that disallows sending them over HTTP(no S). This is problematic in local development,

### Additional contract requirements

- Add a public function `UseLocalDev()` in package `safehttp` (import path `github.com/google/go-safeweb/safehttp`). It enables local-development mode. It must be called before a `ServeMux` is created; calling it after the framework has been initialized panics.
- Add a public function `IsLocalDev() bool` in package `safehttp`. It reports whether the framework is currently configured for local development, returning true after `UseLocalDev()` has been called.
- In local-development mode, the safe cookie defaults are non-secure (the `Secure` option is not set).
- In local-development mode, the HSTS plugin does not redirect HTTP requests to HTTPS and does not add the `Strict-Transport-Security` header to responses.
