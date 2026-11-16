ArrayVec from slice
How can i create an ArrayVec from a slice?
There is no ArrayVec::from(&[T])

### Additional contract requirements

- `ArrayVec<A>` implements `std::convert::TryFrom<&[A::Item]>` where `A: Array` and `A::Item: Clone`, with associated error type `CapacityError`. This enables the standard `TryInto` conversion, for example `let v: ArrayVec<[i32; 4]> = (&[1, 2, 3] as &[_]).try_into().unwrap();`.
- Converting a slice whose length is at most `A::CAPACITY` succeeds and yields an `ArrayVec` containing the same elements in the same order.
- Converting a slice whose length is greater than `A::CAPACITY` fails with `Err(CapacityError)`.
