"implementation hidden" feature not working when adding function to a string
You can print the implementation of any function just by adding it to an empty string `""`.
For instance:
```JavaScript
//input
make_binary_tree_node+"";
//output
"function make_binary_tree_node(left, value, right) {
    if (!is_binary_tree(left)) {
        throw new Error("Left subtree is not a valid binary tree");
    } else if (!is_binary_tree(right)) {
        throw new Error("Right subtree is not a valid binary tree");
    }
    return list(left, value, right);
}"
```
[HIDDEN] (Although in the Source language description it says any type can be added to a string, but a function added to a string should be censored.)

### Additional contract requirements

- For `pair + "123"`, the finished value must be exactly `function pair(x, xs) {\n\t[implementation hidden]\n}123`.
- For `"123" + list(4, 5, 6)`, the finished value must be exactly `123[4, [5, [6, []]]]`.
