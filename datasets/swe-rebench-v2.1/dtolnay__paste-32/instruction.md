paste 0.1.13 is not backwards compatible
The new version released yesterday (0.1.13) breaks dependent modules. For example jemalloc-ctl compiles with paste 0.1.12, but not with 0.1.13:
```
   Compiling jemalloc-ctl v0.3.3
error: expected identifier, found `Mib<[usize; 2]>`
##[error]  --> /home/runner/.cargo/registry/src/github.com-1ecc6299db9ec823/jemalloc-ctl-0.3.3/src/macros.rs:8:9
   |
8  | /          paste::item! {
9  | |              $(#[$doc])*
10 | |              #[allow(non_camel_case_types)]
11 | |              pub struct $id;
...  |
39 | |              pub struct [<$id _mib>](pub ::keys::$mib);
40 | |          }
   | |__________^
   |
  ::: /home/runner/.cargo/registry/src/github.com-1ecc6299db9ec823/jemalloc-ctl-0.3.3/src/arenas.rs:3:1
   |
3  |  / option! {
4  |  |     narenas[ str: b"arenas.narenas\0", non_str: 2 ] => libc::c_uint |
5  |  |     ops: r |
6  |  |     docs:
...   |
26 |  |     mib_docs: /// See [`narenas`].
27 |  | }
   |  |_- in this macro invocation
```

The above compiler error was fixed by forcing Cargo to select version 0.1.12 of paste instead of 0.1.13.

Based on cargo's scheme to by default select the "maximum compatible" version based semantic versioning, if a backwards-incompatible change needs to be made, a new minor version should be used (e.g., 0.2.0) so that dependent crates do not break. Thanks!

### Additional contract requirements

`paste::item!` must accept a generic type as the segment following a path separator in a generated item. For example, a field type equivalent to `::keys::Mib<[usize; 2]>` must compile when `Mib<[usize; 2]>` is supplied after `::keys::`.
