Can't return Result<Box<T>>
I am trying to return a Result<Box< T >> and I am getting the below compile errors.
>expected struct `std::boxed::Box`, found enum `std::result::Result`
>expected enum `std::result::Result`, found *-ptr

I have tried setting the return type to Result<T> and Box<T> and both compile fine.

Here is a simple proof.

```rust
#[cxx::bridge()]
mod test {
    struct Test {
        size: usize,
    }

    extern "Rust" {
        fn test() -> Result<Box<Test>>;
    }
}

fn test() -> Result<Box<test::Test>> {
    Ok(Box::<test::Test>::new(test::Test{size: 0}))
}
```

The reason I want to return a Result<Box<T>> is because in my use case T is a rust opaque type, but I made T a shared type to check that both Result<T> and Box<T> compile fine where Result<Box<T>> doesn't.
