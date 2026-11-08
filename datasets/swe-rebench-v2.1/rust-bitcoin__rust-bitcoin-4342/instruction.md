Make sure `minimal_non_dust` doesn't return an `Option` before release
In https://github.com/rust-bitcoin/rust-bitcoin/pull/4164 we changed the signature of `minimal_non_dust` to make refactors easier.

However, this function is nearly impossible to make panic (unlike `minimal_non_dust_custom` which is pretty easy) since you need a script on the order of magnitude of 600 petabytes. **Plus** we just deprecated `dust_value` telling users to switch to `minimal_non_dust` so it'd be pretty obnoxious for us to then change the signature.
