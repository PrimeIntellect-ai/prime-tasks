Day 470
Good morning! Here's your coding interview problem for today.

This problem was asked by Google.

Given an array of numbers and an index `i`, return the index of the nearest larger number of the number at index `i`, where distance is measured in array indices.

For example, given `[4, 1, 3, 5, 6]` and index `0`, you should return `3`.

If two distances to larger numbers are the equal, then return any one of them. If the array at `i` doesn't have a nearest larger integer, then return `null`.

Follow-up: If you can preprocess the array, can you do this in constant time?

### Additional contract requirements

- The solution is provided in Go package `day470` as two functions with these signatures:
  - `ClosestLargerNumberIndexBrute(nums []int, targetIndex int) int`
  - `PreprocessClosestLargerNumberIndex(nums []int) []int`
- For a valid index `i` (`0 <= i < len(nums)`), the result is the index of a strictly larger value than `nums[i]` whose distance from `i` (the difference of the indices) is the smallest among all strictly larger values. A value equal to `nums[i]` does not count as larger.
- When several strictly larger values are equally near, returning the index of any one of them is acceptable.
- When no strictly larger value exists, the result is `-1`, since the result is an `int`.
- `PreprocessClosestLargerNumberIndex` returns a slice of the same length as the input, where element `i` is a valid answer for index `i` under the rules above, so that each later query is a single lookup into the returned slice.
