Type inference error with Tuples and float/ints
If you destructure a number from a tuple, the type-inference seems to not be able to treat it as both a float and an int.

```elm
module Main exposing (foo)

foo asInt =
    let
        myGoodNumber =
            216

        ( myBadNumber, _ ) =
            ( 216, 0 )
    in

    if asInt then
        String.fromInt myGoodNumber
            ++ String.fromInt myBadNumber

    else
        String.fromFloat myGoodNumber
            ++ String.fromFloat myBadNumber
```

## Expected Behavior
`elm make` doesn't compile with any errors here.

## Current Behavior
`elm-language-server` throws an error:
<img width="1075" alt="CleanShot 2022-05-23 at 13 28 32@2x" src="https://user-images.githubusercontent.com/446007/169875136-19da07aa-8d5f-43b0-8eec-780068b4fc39.png">

## Context
It seems that Elm does some type-punning for constant numbers, and lets them be both Floats and Ints. The type inference code here seems to mostly do the same thing, except when destructuring those numbers. Perhaps this breaks for record and opaque type destructuring as well?

### Additional contract requirements

- When an explicitly annotated `number` value is passed to both `String.fromInt` and `String.fromFloat`, report `Diagnostics.TypeMismatch` with arguments `["Float", "Int"]`.
