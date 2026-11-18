#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick
    pip3 install pytest networkx pytesseract flask requests pillow

    mkdir -p /app
    mkdir -p /home/user

    # Generate the image with the requirements
    convert -background white -fill black -pointsize 36 label:"METRIC: pagerank, ALPHA: 0.85" /app/task_req.png

    # Create the dataset
    cat << 'EOF' > /app/dataset.jsonl
{"src": "A", "dst": ["B", "C"]}
{"src": "B", "dst": ["C", "D"]}
{"src": "C", "dst": ["A"]}
{"src": "D", "dst": ["C"]}
EOF

    # Create the buggy script
    cat << 'EOF' > /home/user/process.py
import json
import networkx as nx

def build_graph(file_path):
    G = nx.DiGraph()
    nodes = []
    with open(file_path, 'r') as f:
        for line in f:
            data = json.loads(line)
            nodes.append(data['src'])
            G.add_node(data['src'])

    # BUG: Implicit cross join adding edges everywhere
    for n1 in nodes:
        for n2 in nodes:
            if n1 != n2:
                G.add_edge(n1, n2)
    return G

# TODO: Compute metric and serve
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /home/user
    chmod -R 777 /app
