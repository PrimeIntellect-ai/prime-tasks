jit json import/export
I would consider the functions `jit_data` and `jit_graph` to be their inverses, so that
```
import networkx as nx
nx.jit_graph(nx.jit_data(nx.Graph()))
```
works.

Instead, it produces a TypeError (nx 2.2), because jit_data is a function `nx graph -> json string`, while jit_graph is a function `json object -> nx graph`, so that the correct program would be
```
import networkx as nx
import json
nx.jit_graph(json.loads(nx.jit_data(nx.Graph())))
```

This is documented, but in my view unexpected and incoherent behavior. I'm pretty new to networkx and are not familiar with your design philosophy, but see the options
* to add a clarifying note in the documentation OR
* return the json object in `jit_data` OR
* [HIDDEN].

What are your opinions on this?
I am willing to submit a PR (but probably it is just easier for you to make that oneline-commit, so that's also fine :))

### Additional contract requirements

- Passing the output of `jit_data` directly to `jit_graph` must reconstruct a graph equivalent to the original.
