BUG: newick trees with the same support values are incorrectly assigned suffixes
**Describe the bug**
When a supported newick tree provided, the parser will incorrectly add suffix to nodes with the same support value.

**To Reproduce**
```
>>> import cogent3

>>> tree = cogent3.make_tree("((a,b)100, (c,d)100);", name_nodes=True)
>>> print(tree.to_rich_dict())

```
it gives:

"{'newick': '((a,b)node1,(c,d)node2)', 'edge_attributes': {'a': {'length': None}, 'b': {'length': None},
'node1': {'length': None, 'support': **_100.0_**}, 'c': {'length': None}, 'd': {'length': None},
'node2': {'length': None, 'support': **_100.2_**},
'root': {'length': None}}, 'type': 'cogent3.core.tree.PhyloNode', 'version': '2024.7.19a9'}"
