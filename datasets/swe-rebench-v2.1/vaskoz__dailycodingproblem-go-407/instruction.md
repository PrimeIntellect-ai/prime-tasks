Day 196
Good morning! Here's your coding interview problem for today.

This problem was asked by Apple.

Given the root of a binary tree, find the most frequent subtree sum. The subtree sum of a node is the sum of all values under a node, including the node itself.

For example, given the following tree:
```
  5
 / \
2  -5
```
Return `2` as it occurs twice: once as the left leaf, and once as the sum of `2 + 5 - 5`.

### Additional contract requirements

Provide the operation as `MostFrequentSubtreeSum(head *BinaryTree) int`. `BinaryTree` is a public input type with a `Value int` field and `Left` and `Right` fields of type `*BinaryTree`.
