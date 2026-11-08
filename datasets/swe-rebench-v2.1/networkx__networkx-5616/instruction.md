Inconsistent implementation of Euler algorithms
According to my research, having an Euler Circuit and/or Euler Path does not require a graph to be connected. Instead, it is enough that all of its vertices **with nonzero degree** belong to a single connected component. Nevertheless, there are some resources which states that a graph can have Euler Path and/or Euler Circuit  iff it is connected.

In the doc_string, it is stated that `has_eulerian_path` method follows the first opinion.
```
A directed graph has an Eulerian path iff:
- at most one vertex has out_degree - in_degree = 1,
- at most one vertex has in_degree - out_degree = 1,
- every other vertex has equal in_degree and out_degree,
- and all of its vertices with nonzero degree belong to a single connected component of the underlying undirected graph.

An undirected graph has an Eulerian path iff:
- exactly zero or two vertices have odd degree,
- and all of its vertices with nonzero degree belong to a single connected component.
```

However, when we look at the source code, we see that it weirdly requires connectedness for undirected graphs but not for directed ones. Here is the related part:

```
  [HIDDEN]
```
[HIDDEN]
As a result, following examples return different results:

```
>>> G = nx.DiGraph([(0, 1), (1, 2), (2, 0)])
>>> G.add_node(3)
>>> nx.draw(G)
>>> nx.has_eulerian_path(G)
True
```
![image](https://user-images.githubusercontent.com/79102788/166156024-a534f467-beb5-42f1-9caa-64d275c6f65f.png)
```
>>> G = nx.Graph([(0, 1), (1, 2), (0, 2)])
>>> G.add_node(3)
>>> nx.draw(G)
>>> nx.has_eulerian_path(G)
False
```
![image](https://user-images.githubusercontent.com/79102788/166155621-738726bd-ef3f-413a-8543-923065724b3c.png)


On the other hand, `is_eulerian` method requires connectedness for both graph types. IMO, there is an incosistency in the source code. If the first approach is to be accepted, it should be implemented both for Euler Paths and Euler Circuits since an Euler Circuit is nothing but an Euler Path that starts and ends at the same vertex. If you think that connectedness must be a condition, it should be implemented for both directed and undirected graph types.

@rossbar @dschult @MridulS

### Additional contract requirements

The required resolution of the inconsistency is to require connectedness for both directed and undirected graphs, applied consistently to Euler paths and Euler circuits. A graph that contains an isolated vertex (a vertex with no incident edges) is not considered to have an Eulerian path or an Eulerian circuit, even when all of its vertices with nonzero degree belong to a single connected component.

- `has_eulerian_path(G)` returns `False` when `G` contains an isolated vertex, for both directed and undirected graphs.
- `is_eulerian(G)` returns `False` when `G` contains an isolated vertex, for both directed and undirected graphs.
