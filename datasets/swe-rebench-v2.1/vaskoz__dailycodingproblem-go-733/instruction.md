Day 344
Good morning! Here's your coding interview problem for today.

This problem was asked by Adobe.

You are given a tree with an even number of nodes. Consider each connection between a parent and child node to be an "edge". You would like to remove some of these edges, such that the disconnected subtrees that remain each have an even number of nodes.

For example, suppose your input was the following tree:
```
   1
  / \
 2   3
    / \
   4   5
 / | \
6  7  8
```
In this case, removing the edge `(3, 4)` satisfies our requirement.

Write a function that returns the _maximum_ number of edges you can remove while still satisfying this requirement.

### Additional contract requirements

In Go, provide an exported function named `MaxRemovedEdgesEvenSubtrees` that accepts the tree as an adjacency map (`map[int]map[int]struct{}`) and returns the maximum number of removable edges as an `int`. The adjacency map represents an undirected tree, with each edge listed in both endpoints’ neighbour sets, and every remaining component after removal must contain an even number of nodes.
