Day 83
Good morning! Here's your coding interview problem for today.

This problem was asked by Google.

Invert a binary tree.

For example, given the following tree:
```
    a
   / \
  b   c
 / \  /
d   e f
```
should become:
```
  a
 / \
 c  b
 \  / \
  f e  d
```

### Additional contract requirements

In Go, provide an `InvertBinaryTree` function that accepts a `*BinaryTree` and inverts that tree in place. `BinaryTree` has exported fields `Value` of type `string`, `Left` of type `*BinaryTree`, and `Right` of type `*BinaryTree`.
