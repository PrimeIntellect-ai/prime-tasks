Day 327
Good morning! Here's your coding interview problem for today.

This problem was asked by Salesforce.

Write a program to merge two binary trees. Each node in the new tree should hold a value equal to the sum of the values of the corresponding nodes of the input trees.

If only one input tree has a node in a given position, the corresponding node in the new tree should match that input node.

### Additional contract requirements

Expose a `BinaryTree` type with the exported fields `Val int`, `Left *BinaryTree`, and `Right *BinaryTree`, and provide `MergeBinaryTrees(one, two *BinaryTree) *BinaryTree`.

The merged tree contains no node at a position where neither input tree has a node. In particular, merging two nil roots returns nil.

Merging must leave both input trees unchanged: after the call, each input still holds its original values and shape.
