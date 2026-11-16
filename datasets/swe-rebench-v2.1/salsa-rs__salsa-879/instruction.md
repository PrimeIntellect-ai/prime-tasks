Crash with BadHash input and multiple changes
```rust
#[salsa::input]
    struct TmpInput {
        pub id: u64,
    }

    #[derive(PartialEq, Eq, PartialOrd, Ord, Debug, Clone)]
    struct BadHash {
        field: u64,
    }

    impl From<u64> for BadHash {
        fn from(value: u64) -> Self {
            Self { field: value }
        }
    }

    impl std::hash::Hash for BadHash {
        fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
            state.write_i16(0);
        }
    }

    #[salsa::tracked(debug)]
    struct Tmp<'db> {
        id: BadHash,
    }

    #[salsa::tracked]
    fn tmp_getter<'db>(db: &'db dyn base_db::BaseDb, input: TmpInput) -> Tmp<'db> {
        Tmp::new(db, input.id(db).into())
    }

    #[test]
    fn generations_test() {
        tracing_subscriber::fmt().init();
        let mut db = TestDatabase::default();
        let input = TmpInput::new(&db, 9);
        dbg!(tmp_getter(&db, input).0);
        input.set_id(&mut db).to(10);
        dbg!(tmp_getter(&db, input).0);
        input.set_id(&mut db).to(9);
        dbg!(tmp_getter(&db, input).0);
    }
```

logs:
```
---- tests::eq_ord_test stdout ----
[test.rs:1077:9] tmp_getter(&db, input).0 = Id(800)
[test.rs:1079:9] tmp_getter(&db, input).0 = Id(800g1)

thread 'resolver::tests::eq_ord_test' panicked at C:\Users\user\.cargo\git\checkouts\salsa-e6f3bb7c2a062968\0414d89\src\tracked_struct.rs:652:53:
cannot delete read-locked id `Id(800)`; value leaked across threads or user functions not deterministic
stack backtrace:
...
```
