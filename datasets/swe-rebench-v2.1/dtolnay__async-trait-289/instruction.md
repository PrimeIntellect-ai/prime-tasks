Outer attributes of generic type / lifetime parameter not respected in async trait async function definition.
Hi sir(s)

Thank you for the awesome crate and also for many other crates you (and your team) had contributed to the Rust ecosystem!

Consider this snippet:

```rust
use {async_trait::async_trait}; // 0.1.86

#[async_trait]
trait AsyncTrait {

    async fn async_fn<#[cfg(test)] T>(#[cfg(test)] t: T) {
        #[cfg(test)]
        let _ = t;
    }
}

trait SyncTrait {

    fn async_fn<#[cfg(test)] T>(#[cfg(test)] t: T) {
        #[cfg(test)]
        let _ = t;
    }
}
```

[Playground](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=0beb91c888a22032c7a4cf683d29a6ac)

For the async function definition `async fn async_fn<#[cfg(test)] T>(#[cfg(test)] t: T) {`, it seems that `#[async_trait]` attribute macro does not respect the outer attribute `#[cfg(test)]` in the generic type parameter 'slot', i.e. `<#[cfg(test)] T>`.

I am not sure if this is a bug or intended.

Thank you.
