Support for sql type DATE
Hi,
I will be great to have the support of the sql type `DATE` in the library.
I imagine this one will be done with `chrono::NaiveDate` since it's the one that is used in the [documentation](https://www.sea-ql.org/SeaORM/docs/generate-entity/entity-structure#column-type).

To give my own example, I have a model `Rate` which have a simple date:

```rust
use chrono::NaiveDate;
use sea_orm::entity::prelude::*;
use sea_orm::DeriveEntityModel;

#[derive(Debug, Clone, PartialEq, DeriveEntityModel)]
#[sea_orm(table_name = "currency_exchange_rate")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub currency_exchange_rate_id: i64,
    pub from_currency: String,
    pub to_currency: String,
    pub rate_date: NaiveDate,
    pub rate: f64,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
```

But this implementation give me a compile error:

```
error[E0277]: the trait bound `NaiveDate: TryGetable` is not satisfied
  --> src/rates/mod.rs:11:35
   |
11 | #[derive(Debug, Clone, PartialEq, DeriveEntityModel)]
   |                                   ^^^^^^^^^^^^^^^^^ the trait `TryGetable` is not implemented for `NaiveDate`
   |
   = note: this error originates in the derive macro `DeriveEntityModel` (in Nightly builds, run with -Z macro-backtrace for more info)
```
