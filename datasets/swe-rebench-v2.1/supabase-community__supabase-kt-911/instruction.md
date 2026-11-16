[Bug]: Arbitrary hash parameters cause hard to catch exception (e.g. expired OTP link)
### General Info

- [x] I checked for similar bug report
- [x] I am using the latest version
- [x] I checked the [troubleshooting](https://github.com/supabase-community/supabase-kt/blob/master/TROUBLESHOOTING.md) page for similar problems

### Version(s)

3.1.4

### Kotlin Target(s) and their respective versions

WasmJs, Js (didn't test)

### What happened? (include your code)

Any hash parameters string that does not lead to creating a session object will cause a crash. This includes the common case of clicking on an expired OTP link. Examples:

- http://localhost:8080/#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired
- http://localhost:8080/#xxx=yyy

It causes a WebAssembly.Exception on wasmJs without any details on where it originates. The exception is caused by the Auth plugin itself inside of its authScope, which is hard to catch.

Code reference: Auth/src/commonMain/kotlin/io/github/jan/supabase/auth/AuthExtensions.kt::Auth.parseSessionFromFragment

Suggested fixes:
- Only create Session from parameters when possible
- Handle expired OTP and notify user
    - auth.sessionStatus seem like a good place
- Possibly there are other supabase related hash parameters that could be handled as well?

Additionally I suggest:
- Consume only used parameters, leave room for custom parameters that can be read by other parts of the application

### Steps To Reproduce (optional)

1. Install the Auth plugin in the supbase client
2. Open the app with non-session-creating hash parameters.

### Relevant log output (optional)

```shell

```

### Additional contract requirements

- Add a public function `consumeHashParameters(parameters: List<String>, url: String): String` in package `io.github.jan.supabase.auth`. It returns a new URL whose fragment has been rebuilt without any `key=value` pair whose key appears in `parameters`; the rest of the fragment is preserved unchanged.
- Add a public function `consumeUrlParameter(parameters: List<String>, url: String): String` in package `io.github.jan.supabase.auth`. It returns a new URL with the listed query parameters removed; other query components remain untouched.
- Add a public extension function `HttpRequestBuilder.redirectTo(url: String)` in package `io.github.jan.supabase.auth`. It adds a `redirect_to` query parameter containing the encoded `url` to the request builder's URL.
- The auth flow must not crash when a URL fragment does not contain the parameters required to create a session (for example an expired OTP link such as `#error=access_denied&error_code=otp_expired&error_description=...`, or an arbitrary fragment such as `#xxx=yyy`). The public function `parseFragmentAndImportSession(fragment: String, onSessionSuccess: (UserSession) -> Unit = {})` in package `io.github.jan.supabase.auth` is the entry point that processes such a fragment; when the fragment cannot produce a session it must return without throwing and without importing a session.
