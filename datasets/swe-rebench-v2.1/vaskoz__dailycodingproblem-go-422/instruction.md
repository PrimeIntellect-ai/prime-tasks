Day 204
Good morning! Here's your coding interview problem for today.

This problem was asked by Amazon.

Given a complete binary tree, count the number of nodes in faster than O(n) time. Recall that a complete binary tree has every level filled except the last, and the nodes in the last level are filled starting from the left.

### Additional contract requirements

- The count must be available as `CountCompleteBinaryTree(tree *CompleteBinaryTree) int` in package `day204`, where `CompleteBinaryTree` is the existing type whose `Left` and `Right` fields hold the child subtrees (nil when a child is absent).
- An empty tree (`nil`) has 0 nodes.
- For a complete binary tree the function returns the exact number of nodes.
- Counting must be faster than linear in the number of nodes: a complete binary tree with around 2^50 nodes must be counted within a few seconds.
