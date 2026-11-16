Calling `quirks::set_port()` with invalid prefix characters unset the port (WPT non-compliance)
In browsers (tested on Chrome, Firefox and Safari), doing the following:

```js
const u = new URL("https://example.com:8000");
u.port = "\u00009000";
console.log(u.port);
```

will show port `8000` (unchanged). This is also tested in the WPT suite here: https://github.com/web-platform-tests/wpt/blob/2a64dae4641fbd61bd4257df460e188f425b492e/url/url-setters-stripping.any.js#L85-L91. That's how the bug came to my attention.

Doing the same using:

```rust
let mut url = url::Url::parse("http://example.com:8000").unwrap();
url::quirks::set_port(&mut url, "\u{0000}9000").unwrap();
assert_eq!(url.port(), Some(8000));
```

will panic with `url.port()` returning `None`.

### Additional contract requirements

- Add a public function `set_port(url: &mut url::Url, new_port: &str) -> Result<(), ()>` in the `url::quirks` module.
- When `new_port` is non-empty and does not start with a digit, `set_port` returns `Err(())` and leaves the URL's port unchanged.
