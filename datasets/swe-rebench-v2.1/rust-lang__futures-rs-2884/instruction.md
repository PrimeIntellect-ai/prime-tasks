`Lines::poll_next` panics if the reader returns an error after returning data
0.3.30:

[HIDDEN] This results in panics on IO failures.

<https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=488083df8fff1bae3dd22cabbb405451>

```rust
use futures::AsyncRead;
use futures::StreamExt;
use futures::AsyncBufReadExt;
use futures::executor::block_on;
use std::task::Poll;

struct BadReader(bool);

impl AsyncRead for BadReader {
    fn poll_read(mut self: std::pin::Pin<&mut Self>, _cx: &mut std::task::Context<'_>, b: &mut [u8]) -> Poll<std::io::Result<usize>> {
        if self.0 {
            return Poll::Ready(Err(std::io::ErrorKind::InvalidInput.into()));
        } else {
            self.0 = true;
            b.fill(b'x');
            Ok(b.len()).into()
        }
    }
}

fn main() {
    let mut lines = futures::io::BufReader::new(BadReader(false)).lines();
    while let Some(_) = block_on(lines.next()) {}
}
```

Output:

```
  Compiling playground v0.0.1 (/playground)
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.66s
     Running `target/debug/playground`
thread 'main' panicked at /playground/.cargo/registry/src/index.crates.io-6f17d22bba15001f/futures-util-0.3.30/src/io/read_line.rs:44:9:
assertion `left == right` failed
  left: 8192
 right: 0
stack backtrace:
   0: rust_begin_unwind
             at /rustc/9b00956e56009bab2aa15d7bff10916599e3d6d6/library/std/src/panicking.rs:645:5
   1: core::panicking::panic_fmt
             at /rustc/9b00956e56009bab2aa15d7bff10916599e3d6d6/library/core/src/panicking.rs:72:14
   2: core::panicking::assert_failed_inner
             at /rustc/9b00956e56009bab2aa15d7bff10916599e3d6d6/library/core/src/panicking.rs:343:17
   3: core::panicking::assert_failed
             at /rustc/9b00956e56009bab2aa15d7bff10916599e3d6d6/library/core/src/panicking.rs:298:5
   4: futures_util::io::read_line::read_line_internal
             at ./.cargo/registry/src/index.crates.io-6f17d22bba15001f/futures-util-0.3.30/src/io/read_line.rs:44:9
   5: <futures_util::io::lines::Lines<R> as futures_core::stream::Stream>::poll_next
             at ./.cargo/registry/src/index.crates.io-6f17d22bba15001f/futures-util-0.3.30/src/io/lines.rs:35:24
   6: futures_util::stream::stream::StreamExt::poll_next_unpin
             at ./.cargo/registry/src/index.crates.io-6f17d22bba15001f/futures-util-0.3.30/src/stream/stream/mod.rs:1638:9
   7: <futures_util::stream::stream::next::Next<St> as core::future::future::Future>::poll
             at ./.cargo/registry/src/index.crates.io-6f17d22bba15001f/futures-util-0.3.30/src/stream/stream/next.rs:32:9
   8: futures_executor::local_pool::block_on::{{closure}}
             at ./.cargo/registry/src/index.crates.io-6f17d22bba15001f/futures-executor-0.3.30/src/local_pool.rs:317:23
   9: futures_executor::local_pool::run_executor::{{closure}}
             at ./.cargo/registry/src/index.crates.io-6f17d22bba15001f/futures-executor-0.3.30/src/local_pool.rs:90:37
  10: std::thread::local::LocalKey<T>::try_with
             at /rustc/9b00956e56009bab2aa15d7bff10916599e3d6d6/library/std/src/thread/local.rs:284:16
  11: std::thread::local::LocalKey<T>::with
             at /rustc/9b00956e56009bab2aa15d7bff10916599e3d6d6/library/std/src/thread/local.rs:260:9
  12: futures_executor::local_pool::run_executor
             at ./.cargo/registry/src/index.crates.io-6f17d22bba15001f/futures-executor-0.3.30/src/local_pool.rs:86:5
  13: futures_executor::local_pool::block_on
             at ./.cargo/registry/src/index.crates.io-6f17d22bba15001f/futures-executor-0.3.30/src/local_pool.rs:317:5
  14: playground::main
             at ./src/main.rs:23:25
  15: core::ops::function::FnOnce::call_once
             at /rustc/9b00956e56009bab2aa15d7bff10916599e3d6d6/library/core/src/ops/function.rs:250:5
note: Some details are omitted, run with `RUST_BACKTRACE=full` for a verbose backtrace.
```

### Additional contract requirements

- A `Lines` stream yields an I/O error as an error item, including when the reader supplied data before failing. Polling the stream again after that error must not panic.
- Each successful line yielded by `Lines` excludes its terminating newline and any carriage return immediately before that newline.
- For valid UTF-8, `read_line` appends the line contents to the supplied string and returns the number of bytes read, including the terminating newline when one was read.
- `read_line` propagates underlying I/O errors and returns an `InvalidData` error when newly read bytes are not valid UTF-8.
- If an incomplete `read_line` future is dropped, the supplied string's original contents remain unchanged. Its original contents also remain unchanged when `read_line` encounters invalid UTF-8.
