`sentry::capture_error` does not capture the backtrace even when the feature is enabled
### Environment

How do you use Sentry?
Self-hosted 21.5.0 and 9.1.2

Which SDK and version?
Rust 0.18 and 0.22 (because of Tokio 0.2 and 1.0)

### Steps to Reproduce

1. Install sentry integration with backtraces enabled
2. Call `sentry::capture_error`
3. Go to sentry, see the absence of stacktrace

- `Cargo.toml`
```toml
sentry = { version = "0.22", features = ["backtrace"] }
```
- `main.rs`
```rust
fn main() {
    sentry::init(("https://my-dsn", sentry::ClientOptions {
        attach_stacktrace: true,
        ..Default::default()
    });
    println!("Sentry installed");

    let error = "thisisnotanumber".parse::<u32>().unwrap_err();
    sentry::capture_error(&error);
}
```

### Expected Result

The stacktrace would be shown in the web ui.

![sentry-backtrace](https://user-images.githubusercontent.com/4009336/116897532-a49e1600-ac35-11eb-8266-eafdf9e22192.png)

### Actual Result

The web UI shows no stacktrace for the issue.

![sentry-nobacktrace](https://user-images.githubusercontent.com/4009336/116897552-ab2c8d80-ac35-11eb-96ab-dc99b8e97c3c.png)

### Fix suggestion

The above screenshot with backtrace was obtained by [HIDDEN]. However, in the case of events made from `capture_error`, they do _not_ contain a backtrace, resulting in no backtrace being attached to the event. The tweak is as follows:

```rust
diff --git a/sentry-backtrace/src/integration.rs b/sentry-backtrace/src/integration.rs
index 49f6826..e6c3a5a 100644
--- a/sentry-backtrace/src/integration.rs
+++ b/sentry-backtrace/src/integration.rs
@@ -73,7 +73,7 @@ impl Integration for AttachStacktraceIntegration {
         mut event: Event<'static>,
         options: &ClientOptions,
     ) -> Option<Event<'static>> {
[HIDDEN]
[HIDDEN]
```

While this works, it may not be ideal as I feel like this is not really what the `threads` field is for. [HIDDEN]

### Additional contract requirements

- With backtrace support enabled and `attach_stacktrace: true`, calling `sentry::capture_error` must produce an event that carries a stacktrace.
