Redis 0.20.1 with tokio-comp feature failed to build on CentOS7
OS: CentOS7
Rust: 1.54.0
Cargo: 1.54.0
Cargo deps: redis = { version = "0.20.1", features = ["tokio-comp"] }

```
error[E0412]: cannot find type `BoxFuture` in module `futures_util::future`
   --> /root/.cargo/registry/src/github.com-1ecc6299db9ec823/redis-0.20.2/src/types.rs:529:53
    |
529 |   pub type RedisFuture<'a, T> = futures_util::future::BoxFuture<'a, RedisResult<T>>;
    |                                                       ^^^^^^^^^ help: a trait with a similar name exists: `Future`

error[E0599]: no method named `boxed` found for opaque type `impl futures_util::Future` in the current scope
   --> /root/.cargo/registry/src/github.com-1ecc6299db9ec823/redis-0.20.2/src/aio.rs:531:10
    |
531 |         .boxed()
    |          ^^^^^ method not found in `impl futures_util::Future`
    |
    = help: items from traits can only be used if the trait is implemented and in scope
note: `RedisRuntime` defines an item `boxed`, perhaps you need to implement it
   --> /root/.cargo/registry/src/github.com-1ecc6299db9ec823/redis-0.20.2/src/aio.rs:56:1
    |
56  | pub(crate) trait RedisRuntime: AsyncStream + Send + Sync + Sized + 'static {
    | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

error[E0599]: no method named `boxed` found for opaque type `impl futures_util::Future` in the current scope
   --> /root/.cargo/registry/src/github.com-1ecc6299db9ec823/redis-0.20.2/src/aio.rs:581:10
    |
581 |         .boxed()
    |          ^^^^^ method not found in `impl futures_util::Future`
    |
    = help: items from traits can only be used if the trait is implemented and in scope
note: `RedisRuntime` defines an item `boxed`, perhaps you need to implement it
   --> /root/.cargo/registry/src/github.com-1ecc6299db9ec823/redis-0.20.2/src/aio.rs:56:1
    |
56  | pub(crate) trait RedisRuntime: AsyncStream + Send + Sync + Sized + 'static {
    | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

error[E0599]: no method named `boxed` found for opaque type `impl futures_util::Future` in the current scope
   --> /root/.cargo/registry/src/github.com-1ecc6299db9ec823/redis-0.20.2/src/aio.rs:895:10
    |
895 |         .boxed()
    |          ^^^^^ method not found in `impl futures_util::Future`
    |
    = help: items from traits can only be used if the trait is implemented and in scope
note: `RedisRuntime` defines an item `boxed`, perhaps you need to implement it
   --> /root/.cargo/registry/src/github.com-1ecc6299db9ec823/redis-0.20.2/src/aio.rs:56:1
    |
56  | pub(crate) trait RedisRuntime: AsyncStream + Send + Sync + Sized + 'static {
    | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

error[E0599]: no method named `boxed` found for opaque type `impl futures_util::Future` in the current scope
   --> /root/.cargo/registry/src/github.com-1ecc6299db9ec823/redis-0.20.2/src/aio.rs:918:10
    |
918 |         .boxed()
    |          ^^^^^ method not found in `impl futures_util::Future`
    |
    = help: items from traits can only be used if the trait is implemented and in scope
note: `RedisRuntime` defines an item `boxed`, perhaps you need to implement it
   --> /root/.cargo/registry/src/github.com-1ecc6299db9ec823/redis-0.20.2/src/aio.rs:56:1
    |
56  | pub(crate) trait RedisRuntime: AsyncStream + Send + Sync + Sized + 'static {
    | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

   Compiling hyper v0.14.12
error: aborting due to 5 previous errors

Some errors have detailed explanations: E0412, E0599.
For more information about an error, try `rustc --explain E0412`.
error: could not compile `redis`

To learn more, run the command again with --verbose.
warning: build failed, waiting for other jobs to finish...
error: build failed

```

### Additional contract requirements

The crate must compile with the `tokio-comp` feature enabled using the reported Redis 0.20.1 dependency configuration on CentOS 7 with Rust 1.54.0 and Cargo 1.54.0.
