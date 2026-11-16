The program crashed after using the "join" function.
- [ ] Note that this crate implements the [URL Standard](https://url.spec.whatwg.org/) not RFC 1738 or RFC 3986

**Describe the bug**
A clear and concise description of what the bug is. Include code snippets if possible.

This is the version of url:
```toml
[dependencies]
url = "=2.3.1"
```

This is the code that trigger bugs:
```rust
fn main() {
    let s1 = "fIlE:p:?../";
    let s2 = "../";
    let url = url::Url::parse(s1).unwrap();
    let _ = url::Url::join(&url, s2);
}
```

Run this code, we will get the error message below:
```
thread 'main' panicked at 'assertion failed: self.serialization.as_bytes()[segment_start - 1] == b\'/\'', /home/yxz/.cargo/registry/src/mirrors.ustc.edu.cn-61ef6e0cd06fb9b8/url-2.3.1/src/parser.rs:1227:21
```
