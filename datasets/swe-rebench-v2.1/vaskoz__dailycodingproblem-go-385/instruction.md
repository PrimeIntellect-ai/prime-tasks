Day 186
Good morning! Here's your coding interview problem for today.

This problem was asked by Microsoft.

Given an array of positive integers, divide the array into two subsets such that the difference between the sum of the subsets is as small as possible.

For example, given `[5, 10, 15, 20, 25]`, return the sets `{10, 25}` and `{5, 15, 20}`, which has a difference of 5, which is the smallest possible difference.

### Additional contract requirements

Expose the operation as `SubsetsSmallestDifference([]int) ([]int, []int)`. Given an input slice of positive integers, return two subsets that together contain every input element exactly once. Their sums must have the smallest possible absolute difference among all such partitions.
