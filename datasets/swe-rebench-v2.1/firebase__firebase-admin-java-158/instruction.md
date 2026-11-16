Support Configurable Timeouts
Admin SDK uses Google Java HTTP client to make outbound HTTP connections. But we currently do not set the connection and read timeout for outbound requests. These need to be configurable via `FirebaseOptions` or a similar API.

### Additional contract requirements

- `FirebaseOptions.Builder.setConnectTimeout(int connectTimeout)` in `com.google.firebase.FirebaseOptions.Builder` configures the connection timeout, in milliseconds, applied to outbound REST calls. It returns the `Builder` for method chaining and throws `IllegalArgumentException` if the value is negative.
- `FirebaseOptions.Builder.setReadTimeout(int readTimeout)` in `com.google.firebase.FirebaseOptions.Builder` configures the read timeout, in milliseconds, applied to outbound REST calls. It returns the `Builder` for method chaining and throws `IllegalArgumentException` if the value is negative.
- `FirebaseOptions.getConnectTimeout()` in `com.google.firebase.FirebaseOptions` returns the configured connection timeout in milliseconds, or `0` if none was set.
- `FirebaseOptions.getReadTimeout()` in `com.google.firebase.FirebaseOptions` returns the configured read timeout in milliseconds, or `0` if none was set.
- `FirebaseRequestInitializer` in `com.google.firebase.internal` is a public class implementing `com.google.api.client.http.HttpRequestInitializer`, with a public constructor `FirebaseRequestInitializer(FirebaseApp app)`. Its `initialize(HttpRequest request)` method adds the `Authorization` header using the app's credentials and sets the request's connect and read timeouts to the values configured in the app's `FirebaseOptions`.
