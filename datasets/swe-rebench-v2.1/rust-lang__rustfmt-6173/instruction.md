rustfmt removes inner attributes from inline const blocks
Clippy unfortunately warns about asserts whose conditions can be evaluated at compile-time even in inline const blocks. It's a [known issue](https://github.com/rust-lang/rust-clippy/issues/8159), it'll hopefully be solved at some point.

In the meantime, if one wishes to perform such compile-time asserts without disabling the lint globally, one can simply allow the offending lint:

```rust
fn main() {
    const {
        #![allow(clippy::assertions_on_constants)]

        assert!(1 < 2);
    }
}
```

Unfortunately, running rustfmt on the above will simply remove the attribute ([try it on the playground](https://play.rust-lang.org/?version=nightly&mode=debug&edition=2021&gist=cd1afc21b1eb34711d4ad0175658624f)), resulting in:

```rust
fn main() {
    const {
        assert!(1 < 2);
    }
}
```

And then Clippy nags at us again :'(

With inline const blocks due to being stabilized for 1.79 (in 6 weeks), it would be nice to fix rustfmt to not eat their code away.

### Meta

rustfmt version:
```
1.7.0-nightly (2024-05-03 d2d24e3)
```

<!-- TRIAGEBOT_START -->

<!-- TRIAGEBOT_ASSIGN_START -->

<!-- TRIAGEBOT_ASSIGN_DATA_START$${"user":"WeiTheShinobi"}$$TRIAGEBOT_ASSIGN_DATA_END -->

<!-- TRIAGEBOT_ASSIGN_END -->
<!-- TRIAGEBOT_END -->
