[HIDDEN]
Hi networkx folks,

I found the init function of DiGraph [here](https://github.com/networkx/networkx/blob/master/networkx/classes/digraph.py#L303) is interesting. [HIDDEN] Is this a bug? My use case is try to hook network's DiGraph to notify my other components of when a node and edge is being added to the graph. My current solution is to subclass the DiGraph and replace the four dict structures with my own dict. However, because of this logic, it is harder to distinguish between node and edge addition/removal. Would you please have a look? Thank you.

-Minjie

### Additional contract requirements

- For a `DiGraph` subclass with distinct `node_dict_factory` and `adjlist_outer_dict_factory`, the outer mappings backing its successors and predecessors must be instances of `adjlist_outer_dict_factory`.
