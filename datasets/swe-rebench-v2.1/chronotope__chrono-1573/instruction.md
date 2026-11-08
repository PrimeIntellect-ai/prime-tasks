0.4.37 semver-incompatibly removes trait bounds on `DateTime`
Hello,

The following code compile in 0.4.35 but breaks in 0.4.37:

```rust
use chrono::TimeZone;
use chrono::DateTime;

#[derive(Clone, Debug)]
pub struct MyDateTime<T: TimeZone>(DateTime<T>);

impl<T: TimeZone> Copy for MyDateTime<T> where T::Offset: Copy {}
```

With 0.4.37:
```
error[E0204]: the trait `Copy` cannot be implemented for this type
 --> src/main.rs:7:28
  |
5 | pub struct MyDateTime<T: TimeZone>(chrono::DateTime<T>);
  |                                    ------------------- this field does not implement `Copy`
6 |
7 | impl<T: TimeZone> Copy for MyDateTime<T> where T::Offset: Copy {}
  |                            ^^^^^^^^^^^^^
  |
note: the `Copy` impl for `DateTime<T>` requires that `T: Copy`
 --> src/main.rs:5:36
  |
5 | pub struct MyDateTime<T: TimeZone>(chrono::DateTime<T>);
  |                                    ^^^^^^^^^^^^^^^^^^^
help: consider further restricting this bound
  |
7 | impl<T: TimeZone + Copy> Copy for MyDateTime<T> where T::Offset: Copy {}
```
This is probably due to https://github.com/chronotope/chrono/pull/1492
