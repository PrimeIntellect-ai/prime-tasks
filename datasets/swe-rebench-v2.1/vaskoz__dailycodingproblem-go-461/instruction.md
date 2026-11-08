Day 223
Good morning! Here's your coding interview problem for today.

This problem was asked by Palantir.

Typically, an implementation of in-order traversal of a binary tree has O(h) space complexity, where h is the height of the tree. Write a program to compute the in-order traversal of a binary tree using O(1) space.

### Additional contract requirements

Provide a `BinaryTree` type with `Value interface{}`, `Left`, and `Right` child pointers, and expose `InorderMorrisTraversal(root *BinaryTree) []interface{}` in package `day223`. The returned values must be in in-order sequence (left subtree, node, right subtree). The traversal must use O(1) auxiliary space, apart from storage for the returned values.
