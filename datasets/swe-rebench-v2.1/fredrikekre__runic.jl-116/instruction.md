List of `let` variables not indented
For example,

```julia
let a = 1,
    b = 2
    a + b
end
```

should become

```julia
let a = 1,
        b = 2
    a + b
end
```
