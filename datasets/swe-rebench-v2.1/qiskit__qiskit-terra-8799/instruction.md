small improvement to DAGCircuit.replace_block_with_op()
### What should we add?

Short version:
- [HIDDEN]

Details:
`DAGCircuit.replace_block_with_op(block, op, ...)` internally creates a `new_node` containing `op`, and replaces the `block` of DAG nodes by this `new_node`.

[HIDDEN] This change would be in line with the behavior of `DAGCircuit.substitute_node()`, which does return its internal `new_node`. Otherwise, the user does not know the node_id or even the name of the new node, so finding the new node for further manipulations is difficult. (All I can think of is to look along one of the wires for the one node in the new DAG that wasn't in the old DAG... obviously this is cumbersome.) [HIDDEN]

### Additional contract requirements

- `DAGCircuit.replace_block_with_op()` must return the newly created operation node inserted in place of the block.
