Day 363
Good morning! Here's your coding interview problem for today.

This problem was asked by Squarespace.

Write a function, `add_subtract`, which alternately adds and subtracts curried arguments. Here are some sample operations:

```
add_subtract(7) -> 7

add_subtract(1)(2)(3) -> 1 + 2 - 3 -> 0

add_subtract(-5)(10)(3)(9) -> -5 + 10 - 3 + 9 -> 11
```

### Additional contract requirements

In the Go `day363` package, `AddSubtract(n int)` begins the chain. Supply each later integer by calling `__(n int)` on the value returned by the preceding call; that call returns a value that can be chained again. Call `Execute() int` on the chain to obtain its accumulated integer. A chain with no later arguments evaluates to its initial integer. For any number of later arguments, apply addition to the first later argument, subtraction to the second, and continue alternating addition and subtraction.
