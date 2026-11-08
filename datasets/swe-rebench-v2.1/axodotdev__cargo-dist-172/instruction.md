cross compile aarch64-apple-darwin by default
because this is made dead simple by apple (we need only add the target), i think we should include compiling to aarch64-apple-darwin by default, ahead of any larger cross compilation story (which will require more configuration and tooling)

this plus #82/#100  will bring us to target parity with a lot of folks looking to migrate to using cargo-dist
