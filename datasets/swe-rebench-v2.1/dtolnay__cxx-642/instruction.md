Provide a `swap` implementation for types in cxxbridge.h
As recommended in #8. String, Str, and Box should have an efficient `swap`.

### Additional contract requirements

- Unqualified `swap(lhs, rhs)` must be callable through argument-dependent lookup for two `rust::Box<T>` objects, two `rust::String` objects, two `rust::Str` objects, and two `rust::Vec<T>` objects, and must exchange the two values.
- Each of these `swap` overloads returns `void`.
