cargo rustc `--crate-type=lib,cdylib` only uplifts the first artifact kind
### Problem

When manually specifying the crate-type on the command line via `--crate-type=type1,type2` , the artifacts are correctly built (visible in the `deps` directory with a hash), but only the first `crate-type` artifact is uplifted to `target/$profile`.

### Steps

Create a library with
```toml
[lib]
crate-type = [ "lib", "cdylib" ]
```

When building with `cargo build` or `cargo rustc` `target/$profile` contains both the rlib and the cdylib artifacts.

When using cargo rustc `--crate-type=cdylib,lib` instead, only the **first** artifact kind will be uplifted from the deps directory. (When reproducing, remember to run cargo clean after each step to delete the previous artifacts)

```shell
ll target/debug/deps/
total 20728
-rw-r--r--. 1 jschwender jschwender 17622720 Sep  5 11:10 librust_lib_requiring_envvar-80fb9f595b956614.a
-rwxr-xr-x. 2 jschwender jschwender  3594440 Sep  5 11:10 librust_lib_requiring_envvar-80fb9f595b956614.so
-rw-r--r--. 1 jschwender jschwender      397 Sep  5 11:10 rust_lib_requiring_envvar-80fb9f595b956614.d
```

```shell
ll target/debug/
total 3516
drwxr-xr-x. 1 jschwender jschwender     168 Sep  5 11:10 build
drwxr-xr-x. 1 jschwender jschwender     278 Sep  5 11:10 deps
drwxr-xr-x. 1 jschwender jschwender       0 Sep  5 11:10 examples
drwxr-xr-x. 1 jschwender jschwender     142 Sep  5 11:10 incremental
-rw-r--r--. 1 jschwender jschwender     216 Sep  5 11:10 librust_lib_requiring_envvar.d
-rwxr-xr-x. 2 jschwender jschwender 3594440 Sep  5 11:10 librust_lib_requiring_envvar.so
````

The order of the


### Possible Solution(s)

_No response_

### Notes

_No response_

### Version

Tested on stable:

```text
cargo 1.80.0 (376290515 2024-07-16)
release: 1.80.0
commit-hash: 37629051518c3df9ac2c1744589362a02ecafa99
commit-date: 2024-07-16
host: x86_64-unknown-linux-gnu
libgit2: 1.7.2 (sys:0.18.3 vendored)
libcurl: 8.6.0-DEV (sys:0.4.72+curl-8.6.0 vendored ssl:OpenSSL/1.1.1w)
ssl: OpenSSL 1.1.1w  11 Sep 2023
os: Fedora 40.0.0 [64-bit]
```

and nightly:

```
cargo 1.83.0-nightly (c1fa840a8 2024-08-29)
release: 1.83.0-nightly
commit-hash: c1fa840a85eca53818895901a53fae34247448b2
commit-date: 2024-08-29
host: x86_64-unknown-linux-gnu
libgit2: 1.8.1 (sys:0.19.0 vendored)
libcurl: 8.9.0-DEV (sys:0.4.74+curl-8.9.0 vendored ssl:OpenSSL/1.1.1w)
ssl: OpenSSL 1.1.1w  11 Sep 2023
os: Fedora 40.0.0 [64-bit]
```
```
