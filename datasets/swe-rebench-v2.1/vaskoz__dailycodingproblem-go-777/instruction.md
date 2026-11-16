Day 384
Good morning! Here's your coding interview problem for today.

This problem was asked by WeWork.

You are given an array of integers representing coin denominations and a total amount of money. Write a function to compute the fewest number of coins needed to make up that amount. If it is not possible to make that amount, return null.

For example, given an array of `[1,5, 10]` and an amount `56`, return `7` since we can use 5 dimes, 1 nickel, and 1 penny.

Given an array of `[5, 8]` and an amount `15`, return `3` since we can use 5 5-cent coins.

### Additional contract requirements

In Go, provide `FewestCoinsBrute(denom []int, target int) (int, error)`. For a representable target, the returned integer is the minimum number of coins and the error is nil. For a target that cannot be made from the denominations, return a non-nil error; its concrete value and message are not specified.
