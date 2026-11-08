snafu-derive 0.4.2 broke `#[doc(hidden)]`
Hi - big fan of snafu! I have a crate that depends on it, and it looks like I'm getting bit by a backwards-incompatible change in a patch release in snafu (jgallagher/amiquip#12). Specifically, [this code](https://github.com/jgallagher/amiquip/blob/c81c49a5c6ded91c3a8e2816a85c0e2c138b4614/src/errors.rs#L250-L252) compiles if I download snafu 0.4.1 and change its snafu-derive dependency to `"=0.4.1"`, but breaks if it's `"0.4.1"` (the published value) or `"=0.4.2"`.

I looked at the issues and didn't see anyone else mention this, so maybe I'm the only one that got bit by it. I'm about to publish a patch release that just removes the `#[doc(hidden)]` attribute for now, but I am curious if it's still possible to include it somehow with 0.4.3.
