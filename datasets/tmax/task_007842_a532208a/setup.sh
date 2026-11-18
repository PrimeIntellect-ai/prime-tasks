#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk
pip3 install pytest papermill jupyter networkx pandas nbformat

mkdir -p /home/user/sim_project
cd /home/user/sim_project

cat << 'EOF' > lattice.edgelist
0 1
1 2
2 3
3 4
4 0
0 5
0 6
0 7
EOF

cat << 'EOF' > ref_dist.csv
node,prob
0,0.3000
1,0.1250
2,0.1250
3,0.1250
4,0.1250
5,0.0666
6,0.0666
7,0.0666
EOF

cat << 'EOF' > make_notebook.py
import nbformat as nbf

nb = nbf.v4.new_notebook()

code1 = """\
# Parameters
graph_path = "dummy.edgelist"
output_path = "dummy.csv"
"""

code2 = """\
import networkx as nx
import pandas as pd

# Load graph
G = nx.read_edgelist(graph_path, nodetype=int)

# Simple random walk steady state calculation (proportional to degree)
degrees = dict(G.degree())
total_degree = sum(degrees.values())
probs = {node: deg / total_degree for node, deg in degrees.items()}

# Save output
df = pd.DataFrame(list(probs.items()), columns=['node', 'prob'])
df.sort_values('node', inplace=True)
df.to_csv(output_path, index=False)
"""

nb['cells'] = [
    nbf.v4.new_code_cell(code1),
    nbf.v4.new_code_cell(code2)
]

# Tag the first cell as parameters for papermill
nb['cells'][0]['metadata']['tags'] = ['parameters']

with open('diffusion.ipynb', 'w') as f:
    nbf.write(nb, f)
EOF

python3 make_notebook.py
rm make_notebook.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
