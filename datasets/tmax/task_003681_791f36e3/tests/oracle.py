import sys
import pandas as pd
import networkx as nx

if len(sys.argv) < 2:
    sys.exit(1)
df = pd.read_csv(sys.argv[1])
G = nx.from_pandas_edgelist(df, 'source', 'target', create_using=nx.DiGraph())

if 'node_0' not in G:
    print("node,shortest_path")
    sys.exit(0)

lengths = nx.single_source_shortest_path_length(G, 'node_0')
res = pd.DataFrame(list(lengths.items()), columns=['node', 'shortest_path'])
res = res.sort_values(by='node').reset_index(drop=True)
sys.stdout.write(res.to_csv(index=False, lineterminator='\n'))
