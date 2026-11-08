CxxVector::push_back
Adding push_back/pop functionality (and other mutation functionality) to `CxxVector` would be helpful for `CxxVector`s containing types that rust can obtain (e.g. `CxxVector<CxxString>` or `CxxVector<SharedPtr<T>>`). Similarly, `CxxVector::new()` or `CxxVector::default()` would be helpful to create them from Rust.

### Additional contract requirements

- From Rust, a caller holding a pinned mutable reference to an existing `CxxVector<T>` can append an element to the end of that vector by calling a method named `push` with the element passed by value. This must work for element types such as `f64` and shared structs. Once appended, C++ code observes the element at the end of the vector and the vector's size has increased by one.
