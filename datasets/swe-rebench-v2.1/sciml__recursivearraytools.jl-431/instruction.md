similar(::NamedArrayPartition, ::T) yields a `Vector`
I expect this to return a `NamedArrayPartition`. Using `@which` shows that it now uses a fallback method from `Base`.
