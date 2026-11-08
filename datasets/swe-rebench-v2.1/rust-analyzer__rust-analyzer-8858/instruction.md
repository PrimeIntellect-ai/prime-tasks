`#[macro_use] extern crate self` causes a cycle
```rust
#[macro_use]
extern crate self as bla;
```

```
thread '<unnamed>' panicked at 'Internal error, cycle detected:

DatabaseKeyIndex { group_index: 6, query_index: 1, key_index: 12 }
', /home/jonas/.cargo/registry/src/github.com-1ecc6299db9ec823/salsa-0.16.1/src/lib.rs:490:48
stack backtrace:
   0: rust_begin_unwind
   1: std::panicking::begin_panic_fmt
   2: salsa::QueryTable<Q>::get::{{closure}}
   3: <DB as hir_def::db::DefDatabase>::crate_def_map_query::__shim
   4: hir_def::db::crate_def_map_wait
   5: hir_def::nameres::collector::DefCollector::import_all_macros_exported
   6: hir_def::nameres::collector::ModCollector::collect
   7: hir_def::nameres::collector::collect_defs
...
```
