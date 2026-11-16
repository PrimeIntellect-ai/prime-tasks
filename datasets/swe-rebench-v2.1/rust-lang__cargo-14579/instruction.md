Duplicate warnings of `config` on Windows OS When using git-bash
### Problem

This only happend when I use the git bash and in the /tmp folder

Recently, I found the `cargo` on Windows will output the warnings of `config` twice

1、with only `config` exists

```
cargo -vV
warning: `C:\Users\ticktockit\.cargo\config` is deprecated in favor of `config.toml`
note: if you need to support cargo 1.38 or earlier, you can symlink `config` to `config.toml`
warning: `C:\Users\ticktockit\.cargo\config` is deprecated in favor of `config.toml`
note: if you need to support cargo 1.38 or earlier, you can symlink `config` to `config.toml`
cargo 1.83.0-nightly (c1fa840a8 2024-08-29)
release: 1.83.0-nightly
commit-hash: c1fa840a85eca53818895901a53fae34247448b2
commit-date: 2024-08-29
host: x86_64-pc-windows-msvc
libgit2: 1.8.1 (sys:0.19.0 vendored)
libcurl: 8.9.0-DEV (sys:0.4.74+curl-8.9.0 vendored ssl:Schannel)
os: Windows 10.0.22631 (Windows 11 CoreCountrySpecific) [64-bit]
```

2. both `config` and `config.toml` exist

```
cargo -vV
warning: both `C:\Users\ticktockit\.cargo\config` and `C:\Users\ticktockit\.cargo\config.toml` exist. Using `C:\Users\ticktockit\.cargo\config`
warning: both `C:\Users\ticktockit\.cargo\config` and `C:\Users\ticktockit\.cargo\config.toml` exist. Using `C:\Users\ticktockit\.cargo\config`
cargo 1.83.0-nightly (c1fa840a8 2024-08-29)
release: 1.83.0-nightly
commit-hash: c1fa840a85eca53818895901a53fae34247448b2
commit-date: 2024-08-29
host: x86_64-pc-windows-msvc
libgit2: 1.8.1 (sys:0.19.0 vendored)
libcurl: 8.9.0-DEV (sys:0.4.74+curl-8.9.0 vendored ssl:Schannel)
os: Windows 10.0.22631 (Windows 11 CoreCountrySpecific) [64-bit]
```

### Steps

1. make sure the  `C:\Users\[Your PC user account]\.cargo\config` exists
2. using the `git-bash`
3. cd `/tmp`
4. run `cargo -vV`

### Possible Solution(s)

It is not clear if this problem still exists in the latest version, but duplicate information needs to be removed

### Notes

_No response_

### Version

cargo 1.83.0-nightly (c1fa840a8 2024-08-29)
release: 1.83.0-nightly
commit-hash: c1fa840a85eca53818895901a53fae34247448b2
commit-date: 2024-08-29
host: x86_64-pc-windows-msvc
libgit2: 1.8.1 (sys:0.19.0 vendored)
libcurl: 8.9.0-DEV (sys:0.4.74+curl-8.9.0 vendored ssl:Schannel)
os: Windows 10.0.22631 (Windows 11 CoreCountrySpecific) [64-bit]

<!-- TRIAGEBOT_START -->

<!-- TRIAGEBOT_ASSIGN_START -->

<!-- TRIAGEBOT_ASSIGN_DATA_START$${"user":"linyihai"}$$TRIAGEBOT_ASSIGN_DATA_END -->

<!-- TRIAGEBOT_ASSIGN_END -->
<!-- TRIAGEBOT_END -->

### Additional contract requirements

- For either config-file case reported above (a `config` file without the `.toml` extension in the Cargo home directory, or both `config` and `config.toml` existing there), Cargo must print the applicable warning, and its accompanying note where one is shown, only once per invocation. Duplicated copies of the same warning or note are a bug, including when the project being built lives inside the home directory.
