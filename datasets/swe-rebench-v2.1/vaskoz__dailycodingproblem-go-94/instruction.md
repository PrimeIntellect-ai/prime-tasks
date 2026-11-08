Day 42
Good morning! Here's your coding interview problem for today.

This problem was asked by Google.

Given a list of integers S and a target number k, write a function that returns a subset of S that adds up to k. If such a subset cannot be made, then return null.

Integers can appear more than once in the list. You may assume all numbers in the list are positive.

For example, given S = [12, 1, 61, 5, 9, 2] and k = 24, return [12, 9, 2, 1] since it sums up to 24.

### Additional contract requirements

- Provide public functions `SubsetSumBrute(ints []int, k int) []int` and `SubsetSumDP(ints []int, k int) []int` in package `day42`.
- Each function returns a slice containing a subset of `ints` whose elements sum to `k`, or `nil` when no such subset exists. The returned slice must be a sub-multiset of `ints`: each value may be used at most as many times as it appears in `ints`.
- The list may contain zero, and the target `k` may be zero. When a subset summing to zero exists, a non-nil subset must be returned.
