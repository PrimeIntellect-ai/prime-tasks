#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest networkx

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/network_topology.wav "The directed network contains the following links: internet to firewall, firewall to router, router to switch_A, router to switch_B, switch_A to app_server_1, switch_A to app_server_2, switch_B to db_master, app_server_1 to db_master, app_server_2 to db_master, db_master to db_replica, db_replica to backup_storage, app_server_1 to cache_server, cache_server to db_master."

    # Create the oracle script
    cat << 'EOF' > /app/oracle_graph_query.py
import sys
import json
import networkx as nx

edges = [
    ("internet", "firewall"), ("firewall", "router"), ("router", "switch_A"),
    ("router", "switch_B"), ("switch_A", "app_server_1"), ("switch_A", "app_server_2"),
    ("switch_B", "db_master"), ("app_server_1", "db_master"), ("app_server_2", "db_master"),
    ("db_master", "db_replica"), ("db_replica", "backup_storage"),
    ("app_server_1", "cache_server"), ("cache_server", "db_master")
]

G = nx.DiGraph()
G.add_edges_from(edges)
pr = nx.pagerank(G, alpha=0.85)

for line in sys.stdin:
    if not line.strip():
        continue
    try:
        query = json.loads(line)
        action = query.get("action")
        if action == "pagerank":
            node = query.get("node")
            if node in G:
                res = round(pr[node], 4)
            else:
                res = None
            print(json.dumps({"result": res}))
        elif action == "shortest_path":
            source = query.get("source")
            target = query.get("target")
            try:
                path = nx.shortest_path(G, source=source, target=target)
                print(json.dumps({"result": path}))
            except (nx.NetworkXNoPath, nx.NodeNotFound):
                print(json.dumps({"result": None}))
        elif action == "top_in_degree":
            limit = query.get("limit", 0)
            in_degrees = dict(G.in_degree())
            sorted_nodes = sorted(in_degrees.items(), key=lambda x: (-x[1], x[0]))
            res = [n for n, d in sorted_nodes[:limit]]
            print(json.dumps({"result": res}))
        else:
            print(json.dumps({"result": None}))
        sys.stdout.flush()
    except Exception:
        pass
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
