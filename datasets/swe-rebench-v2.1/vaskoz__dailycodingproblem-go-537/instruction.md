Day 260
Good morning! Here's your coding interview problem for today.

This problem was asked by Pinterest.

The sequence `[0, 1, ..., N]` has been jumbled, and the only clue you have for its order is an array representing whether each number is larger or smaller than the last. Given this information, reconstruct an array that is consistent with it. For example, given `[None, +, +, -, +]`, you could return `[1, 2, 3, 0, 4]`.

### Additional contract requirements

Provide `Unjumble(hints []rune) []int` in package `day260`. Each rune clue is `+` when the next number must be larger than the previous number and `-` when it must be smaller. For N clues, return a permutation of the integers from 0 through N whose adjacent comparisons satisfy the clues.
