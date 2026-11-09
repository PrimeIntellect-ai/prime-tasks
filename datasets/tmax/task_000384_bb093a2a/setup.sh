#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib networkx Pillow

    mkdir -p /app
    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /app/generate.py
import random
from rdflib import Graph, URIRef
from PIL import Image, ImageDraw

g = Graph()
nodes = [URIRef(f"http://example.org/node/{i}") for i in range(150)]
predicates = [
    URIRef("http://example.org/ontology/cites"),
    URIRef("http://example.org/ontology/coauthor"),
    URIRef("http://example.org/ontology/retracted")
]

for _ in range(600):
    s = random.choice(nodes)
    o = random.choice(nodes)
    if s != o:
        p = random.choice(predicates)
        g.add((s, p, o))

g.serialize(destination='/home/user/dataset.ttl', format='turtle')

img = Image.new('RGB', (800, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), "EXCLUDE PREDICATE: <http://example.org/ontology/retracted>", fill=(0,0,0))
img.save('/app/filter_rule.png')
EOF

    python3 /app/generate.py

    cat << 'EOF' > /app/oracle_query_distance
#!/usr/bin/env python3
import sys
import networkx as nx
from rdflib import Graph, URIRef

if len(sys.argv) != 3:
    sys.exit(1)

source = URIRef(sys.argv[1])
target = URIRef(sys.argv[2])

g = Graph()
g.parse('/home/user/dataset.ttl', format='turtle')

G = nx.DiGraph()
for s, p, o in g:
    if str(p) != "http://example.org/ontology/retracted":
        G.add_edge(s, o)

try:
    length = nx.shortest_path_length(G, source=source, target=target)
    print(length)
except nx.NetworkXNoPath:
    print("-1")
except nx.NodeNotFound:
    print("-1")
EOF

    chmod +x /app/oracle_query_distance
    chmod -R 777 /home/user
