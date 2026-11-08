Day 336
Good morning! Here's your coding interview problem for today.

This problem was asked by Microsoft.

Write a program to determine how many distinct ways there are to create a max heap from a list of N given integers.

For example, if `N = 3`, and our integers are `[1, 2, 3]`, there are two ways, shown below.
```
  3      3
 / \    / \
1   2  2   1
```

### Additional contract requirements

- Assume the N integers are distinct; count arrangements that differ in the placement of those integers.
- Provide the Go function `PossibleMaxHeaps(n int) int`, where `n` is the number of distinct integers and the return value is the number of max heaps that can be formed.
