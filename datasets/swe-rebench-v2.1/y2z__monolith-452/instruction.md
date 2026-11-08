Panic while parsing srcset with white space
While archiving https://github.blog/engineering/issueops-automate-ci-cd-and-more-with-github-issues-and-actions/, monolith panicked.
We panicked during parsing `srcset`, the offending srcset is
```
srcset="https://github.blog/wp-content/uploads/2024/07/Screenshot-2024-07-23-at-8.42.45 AM.png?w=800 800w, https://github.blog/wp-content/uploads/2024/07/Screenshot-2024-07-23-at-8.42.45 AM.png?w=400 400w, https://github.blog/wp-content/uploads/2024/07/Screenshot-2024-07-23-at-8.42.45 AM.png?w=1032 1032w, https://github.blog/wp-content/uploads/2024/07/Screenshot-2024-07-23-at-8.42.45 AM.png?w=516 516w"
```
It's because there's a pesky zero-width whitespace in it. I'm not sure if this is in-spec tho.
```js
> encodeURI("Screenshot-2024-07-23-at-8.42.45 AM.png")
'Screenshot-2024-07-23-at-8.42.45%E2%80%AFAM.png'
```


```
RUST_BACKTRACE=1 monolith https://github.blog/engineering/issueops-automate-ci-cd-and-more-with-github-issues-and-actions/
....
https://github.blog/wp-content/uploads/2024/07/Screenshot-2024-07-23-at-8.42.45%E2%80%AFAM.png?resize=800%2C425

thread 'main' panicked at /home/x/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/monolith-2.9.0/src/html.rs:184:76:
called `Option::unwrap()` on a `None` value
stack backtrace:
   0: rust_begin_unwind
   1: core::panicking::panic_fmt
   2: core::panicking::panic
   3: core::option::unwrap_failed
   4: monolith::html::embed_srcset
   5: monolith::html::walk_and_embed_assets
   6: monolith::html::walk_and_embed_assets
   7: monolith::html::walk_and_embed_assets
   8: monolith::html::walk_and_embed_assets
   9: monolith::html::walk_and_embed_assets
  10: monolith::html::walk_and_embed_assets
  11: monolith::html::walk_and_embed_assets
  12: monolith::html::walk_and_embed_assets
  13: monolith::html::walk_and_embed_assets
  14: monolith::html::walk_and_embed_assets
  15: monolith::html::walk_and_embed_assets
  16: monolith::html::walk_and_embed_assets
  17: monolith::html::walk_and_embed_assets
  18: monolith::html::walk_and_embed_assets
  19: monolith::core::create_monolithic_document
  20: monolith::main
```
