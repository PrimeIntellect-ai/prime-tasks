#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg cargo rustc
pip3 install pytest

mkdir -p /app
ffmpeg -f lavfi -i aevalsrc=0 -t 1 -metadata ICMT="ETL RULES: 1. Discard any node with status != 'ACTIVE'. If a node is discarded, all edges where it is the 'src' or 'dst' must also be discarded. 2. Filter edges to keep only those with action == 'CONNECT'. 3. Aggregate the remaining edges by outputting an adjacency list mapping 'src' to 'dst' to the sum of 'val'. Output format must be a tightly packed JSON object: {\"src_id\":{\"dst_id\":total_val}} sorted by src_id and dst_id." /app/schema_instructions.wav

cat << 'EOF' > /usr/local/bin/oracle_graph_etl
#!/usr/bin/env python3
import sys, json

def process():
    try:
        data = json.load(sys.stdin)
    except:
        return

    active_nodes = {n['id'] for n in data.get('nodes', []) if n.get('status') == 'ACTIVE'}

    adj = {}
    for e in data.get('edges', []):
        if e.get('action') != 'CONNECT': continue
        src, dst, val = e.get('src'), e.get('dst'), e.get('val', 0)

        if src in active_nodes and dst in active_nodes:
            if src not in adj: adj[src] = {}
            if dst not in adj[src]: adj[src][dst] = 0
            adj[src][dst] += val

    # Sort keys for deterministic output
    sorted_adj = {k: {kk: adj[k][kk] for kk in sorted(adj[k].keys())} for k in sorted(adj.keys())}
    print(json.dumps(sorted_adj, separators=(',', ':')))

if __name__ == '__main__':
    process()
EOF

chmod +x /usr/local/bin/oracle_graph_etl

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
