Input change cause panic on next queries
From Zulip (thanks Andrey for the minimal repro) :

```rust
#[test]
fn hello() {
    use salsa::{Database, DatabaseImpl, Setter};

    #[salsa::input]
    struct Bool {
        value: bool,
    }

    #[salsa::tracked]
    struct True<'db> {}

    #[salsa::tracked]
    struct False<'db> {}

    #[salsa::tracked]
    fn hello(db: &dyn Database, bool: Bool) {
        if bool.value(db) {
            True::new(db);
        } else {
            False::new(db);
        }
    }

    let mut db = DatabaseImpl::new();
    let input = Bool::new(&db, false);
    hello(&mut db, input);
    input.set_value(&mut db).to(true);
    hello(&mut db, input);
}
```

Output :

```
assertion `left == right` failed: page has hidden type `"salsa::table::Page<salsa::tracked_struct::Value<mitki_parse::hello::False>>"` but `"salsa::table::Page<salsa::tracked_struct::Value<mitki_parse::hello::True>>"` was expected
```

Stacktrace in `table.rs` :

```rust
impl dyn TablePage {
    fn assert_type<T: Any>(&self) -> &T {
        assert_eq!( // <-- Assertion failure here
            Any::type_id(self),
            TypeId::of::<T>(),
            "page has hidden type `{:?}` but `{:?}` was expected",
            self.hidden_type_name(),
            std::any::type_name::<T>(),
        );

        // SAFETY: Assertion above
        unsafe { transmute_data_ptr::<dyn TablePage, T>(self) }
    }
}
```
