Day 305
Good morning! Here's your coding interview problem for today.

This problem was asked by Amazon.

Given a linked list, remove all consecutive nodes that sum to zero. Print out the remaining nodes.

For example, suppose you are given the input `3 -> 4 -> -7 -> 5 -> -6 -> 6`. In this case, you should first remove `3 -> 4 -> -7`, then `-6 -> 6`, leaving only `5`.

### Additional contract requirements

- Expose the removal operation as `func RemoveConsecutiveSumZero(head *LL) *LL`.
- Represent each node as `type LL struct { Value int; Next *LL }`.
