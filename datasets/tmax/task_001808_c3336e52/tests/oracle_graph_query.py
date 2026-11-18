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
