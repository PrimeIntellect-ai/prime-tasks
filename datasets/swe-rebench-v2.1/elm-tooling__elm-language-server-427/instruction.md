Handle recursion like the compiler
We need to find a way to handle recursion like the compiler does.

This code is valid in the compiler:
```elm
func : Int -> String
func =
    let
        go n =
            if n == 1 then
                "text"

            else
                func n ++ "more"
    in
    go
```

Our type inference system doesn't allow recursion for functions with no parameters, but it should actually look at the return type of the function. The problem is that we don't know the return type until we recursively check itself.

 https://github.com/elm-tooling/elm-language-server/blob/40bac9ab7aea797a01a7fe5c0e25bce93506769e/src/util/types/typeInference.ts#L654

The solution seems to be non-trivial, so I will be studying the compiler to understand how we can achieve this.
