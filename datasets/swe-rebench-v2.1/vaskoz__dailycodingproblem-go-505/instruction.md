Day 243
Good morning! Here's your coding interview problem for today.

This problem was asked by Etsy.

Given an array of numbers `N` and an integer `k`, your task is to split `N` into `k` partitions such that the maximum sum of any partition is minimized. Return this sum.

For example, given `N = [5, 1, 2, 7, 3, 4]` and `k = 3`, you should return `8`, since the optimal partition is `[5, 1, 2], [7], [3, 4]`.

### Additional contract requirements

Expose the behavior through `MinimizePartitionMaximumSum(nums []int, k int) int`. For valid `k`, partition the input into exactly `k` contiguous, non-empty groups and return the minimum achievable largest group sum.
