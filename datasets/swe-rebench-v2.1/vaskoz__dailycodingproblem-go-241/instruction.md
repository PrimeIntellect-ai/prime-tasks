Day 112
Good morning! Here's your coding interview problem for today.

This problem was asked by Twitter.

Given a binary tree, find the lowest common ancestor (LCA) of two given nodes in the tree. Assume that each node in the tree also has a pointer to its parent.

According to the definition of LCA on Wikipedia: “The lowest common ancestor is defined between two nodes v and w as the lowest node in T that has both v and w as descendants (where we allow a node to be a descendant of itself).”

### Additional contract requirements

Expose a `Node` type with a `Parent *Node` field and a `LowestCommonAncestor(n1, n2 *Node) *Node` function.
