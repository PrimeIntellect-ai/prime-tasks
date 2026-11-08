Add binding for std::weak_ptr
https://en.cppreference.com/w/cpp/memory/weak_ptr/weak_ptr

We support std::shared_ptr from #536, and weak_ptr often occurs in related code.

### Additional contract requirements

- Expose a public Rust type named `WeakPtr` that can be used in C++ bridge declarations for `std::weak_ptr<T>`.
- Support weak pointers for the target types that otherwise support shared pointers and `std::weak_ptr`.
- A weak pointer must not keep its target alive. While a strong owner exists, it must be possible to obtain a shared owner from the weak pointer; once all strong owners are gone, that operation must produce an empty shared pointer.
