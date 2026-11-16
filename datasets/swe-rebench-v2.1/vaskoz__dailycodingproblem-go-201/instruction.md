Day 96
Good morning! Here's your coding interview problem for today.

This problem was asked by Microsoft.

Given a number in the form of a list of digits, return all possible permutations.

For example, given `[1,2,3]`, return `[[1,2,3],[1,3,2],[2,1,3],[2,3,1],[3,1,2],[3,2,1]]`.

### Additional contract requirements

- Add a public function `HeapsAlgorithmRecursive(digits []int) <-chan []int` in package `day96` (file `day96/problem.go`).
- Add a public function `HeapsAlgorithmIterative(digits []int) <-chan []int` in package `day96` (file `day96/problem.go`).
- `digits` is a slice of ints containing at least two elements.
- Each function returns a read-only channel that yields every permutation of `digits` as a `[]int` slice, and the channel is closed after all `n!` permutations (where `n = len(digits)`) have been sent.
- `HeapsAlgorithmRecursive` yields the permutations in the order produced by the recursive form of Heap's algorithm.
- `HeapsAlgorithmIterative` yields the permutations in the order produced by the iterative form of Heap's algorithm.
