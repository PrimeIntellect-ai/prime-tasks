Day 146
Good morning! Here's your coding interview problem for today.

This question was asked by BufferBox.

Given a binary tree where all nodes are either 0 or 1, prune the tree so that subtrees containing all 0s are removed.

For example, given the following tree:
```
   0
  / \
 1   0
    / \
   1   0
  / \
 0   0
```
should be pruned to:
```
   0
  / \
 1   0
    /
   1
```
We do not remove the tree at the root or its left child because it still has a 1 as a descendant.

### Additional contract requirements

In Go package `day146`, provide a `BinaryTree` struct whose fields are `Value int` followed by `Left, Right *BinaryTree`, and provide `PruneZeroSubtrees(head *BinaryTree) *BinaryTree`. The function removes every subtree containing only zeros and retains all node values in the remaining tree.
