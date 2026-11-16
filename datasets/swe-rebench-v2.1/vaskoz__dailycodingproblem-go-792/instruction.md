Day 394
Good morning! Here's your coding interview problem for today.

This problem was asked by Uber.

Given a binary tree and an integer `k`, return whether there exists a root-to-leaf path that sums up to k.

For example, given `k = 18` and the following binary tree:
```
    8
   / \
  4   13
 / \   \
2   6   19
```
Return `True` since the path `8 -> 4 -> 6` sums to `18`.

### Additional contract requirements

Expose `RootToLeafTarget(root *IntBinaryTree, target int) bool` in package `day394`. `IntBinaryTree` represents an integer node with `Value int` and optional `Left` and `Right` children of type `*IntBinaryTree`. Node values may be negative and contribute normally to the path sum.
