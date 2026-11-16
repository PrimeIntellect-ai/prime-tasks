transitive_closure loses self loops
Consider the following example:

    import numpy as np
    import networkx as nx
    a = np.array([[0, 1, 1], [1, 0, 1], [1, 1, 0]])
    G = nx.from_numpy_matrix(a, create_using=nx.MultiDiGraph())
    T = nx.transitive_closure(G)
    print(nx.to_numpy_matrix(T))

The transitive closure lacks the expected self loops. Why? (The documentation link does not work, and the docstring implies that self loops should be kept.) By "expected", I mean "according to standard definitions", such as the Wikipedia definition. I anticipate that a different definition is being used, but what is it?

The current [answer at StackExchange](https://stackoverflow.com/questions/52710488/transitive-closure-in-networkx/52711544#52711544) claims this is an implementation error.

### Additional contract requirements

The default transitive closure includes a self-loop for every vertex that belongs to a non-empty directed cycle, and does not add self-loops for vertices that do not belong to such a cycle. Existing input edges and their data are preserved in the returned closure.
