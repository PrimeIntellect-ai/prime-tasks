GEXF output does not round-trip
On master (currently 269c5721100797514aa0469d58e637ec3a29e984) and Python 3.7.3, if I run the following script:
```python
import io, math
import networkx

g = networkx.Graph()
g.add_node(1, weight=float('inf'), data='inf')
g.add_node(2, weight=float('nan'), data='nan')
with io.BytesIO() as f:
	networkx.write_gexf(g, f)
	f.seek(0)
	h = networkx.read_gexf(f, node_type=int)
if h.nodes[1]['data'] != 'inf':
	print(f"h.nodes[1]['data'] == {h.nodes[1]['data']!r} != 'inf'")
if h.nodes[2]['data'] != 'nan':
	print(f"h.nodes[2]['data'] == {h.nodes[2]['data']!r} != 'nan'")
if not isinstance(h.nodes[1]['weight'], float) or not math.isinf(h.nodes[1]['weight']):
	print(f"h.nodes[1]['weight'] == {h.nodes[1]['weight']!r} != float('inf')")
if not isinstance(h.nodes[2]['weight'], float) or not math.isnan(h.nodes[2]['weight']):
	print(f"h.nodes[2]['weight'] == {h.nodes[2]['weight']!r} != float('nan')")
```
I get the following output:

```
h.nodes[1]['data'] == 'INF' != 'inf'
h.nodes[2]['data'] == 'NaN' != 'nan'
h.nodes[1]['weight'] == 'INF' != float('inf')
h.nodes[2]['weight'] == 'NaN' != float('nan')
```

It appears that dc21ca4, which fixed #3573, caused `write_gexf` to write `float('inf')` to XML file as `INF` [HIDDEN], and that `read_gexf` does not cast `float` or `double` XML types to the `float` Python type.

### Additional contract requirements

When reading GEXF node or edge attributes declared as `float` or `double`, return Python `float` values for ordinary finite numbers as well as non-finite values.
