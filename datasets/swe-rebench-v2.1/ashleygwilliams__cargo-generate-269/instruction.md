Creates an empty `.cargo-ok` file
```console
> cargo generate --git https://github.com/Michael-F-Bryan/github-template --name const-arrayvec
> ls const-arrayvec/.cargo-ok
const-arrayvec/.cargo-ok
> cargo generate --version
cargo-generate 0.5.1
```

This file causes issues for `cargo` (though that should be fixed in 1.49) https://github.com/rust-lang/cargo/issues/8816
