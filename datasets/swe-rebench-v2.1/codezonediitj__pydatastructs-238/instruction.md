_left_rotate and _right_rotate in SelfBalancingBinaryTree
#### Description of the problem
<!--Please provide a clear and details information of the bug/data structure to be added.-->
The existing methods of `_left_rotate` and `_right_rotate` in the `SelfBalancingBinaryTree` are not working properly [HIDDEN], which causes conflict in some nodes.

#### Example of the problem
<!--Provide a reproducible example code which is causing the bug to appear. Leave this section if the problem is not a bug.-->
```
>>> tree = SelfBalancingBinaryTree()

>>> tree.insert(5,5)

>>> tree.insert(5.5,5.5)

>>> tree.insert(4.5,4.5)

>>> tree.insert(4.6,4.6)

>>> tree.insert(4.4, 4.4)

>>> tree.insert(4.55, 4.55)

>>> tree.insert(4.65, 4.65)

>>> print(tree)

[(2, 5, 5, 1), (None, 5.5, 5.5, None), (4, 4.5, 4.5, 3), (5, 4.6, 4.6, 6), (None, 4.4, 4.4, None), (None, 4.55, 4.55, None), (None, 4.65, 4.65, None)]
>>> tree._right_rotate(3, 5)

>>> print(tree)

[(2, 5, 5, 1), (None, 5.5, 5.5, None), (5, 4.5, 4.5, 3), (None, 4.6, 4.6, 6), (None, 4.4, 4.4, None), (None, 4.55, 4.55, 3), (None, 4.65, 4.65, None)]
>>> tree.tree[3].parent

5
>>> tree.tree[2].right

3
```

In this example node at index 3 has parent 5, while node at index 2 has 3 as one of its children. Since there cannot be two parents at the same time, this is a conflict.

### Additional contract requirements

- After `_right_rotate(j, k)` the tree must remain a valid linked structure: every non-root node is listed as a child by its parent, every child names its parent correctly, and the in-order sequence of keys is unchanged.
- The same holds after `_left_rotate(j, k)`.
- In `_right_rotate(j, k)`, `j` is the parent and `k` its left child; in `_left_rotate(j, k)`, `j` is the parent and `k` its right child. The node `k` takes the place of `j` under `j`'s own parent, in whichever child slot (left or right) of that parent `j` previously occupied.
- Rotating a node that is the left child of its parent and a node that is the right child of its parent must both be handled correctly.
