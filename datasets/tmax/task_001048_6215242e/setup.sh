#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /app

    # Create the graph engine
    cat << 'EOF' > /app/graph_engine
#!/usr/bin/env python3
import sys, json, time, argparse, csv

def load_csv(path):
    with open(path) as f:
        return list(csv.DictReader(f))

def resolve_field(doc, field):
    parts = field.split('.')
    v = doc
    for p in parts:
        if isinstance(v, dict) and p in v:
            v = v[p]
        else:
            return None
    return v

def run_pipeline(nodes, edges, pipeline):
    colls = {"nodes": nodes, "edges": edges}
    data = [dict(n) for n in nodes]
    for stage in pipeline:
        if "$match" in stage:
            new_data = []
            for d in data:
                time.sleep(0.00001)
                match = True
                for k, v in stage["$match"].items():
                    if resolve_field(d, k) != v:
                        match = False
                        break
                if match:
                    new_data.append(d)
            data = new_data
        elif "$lookup" in stage:
            l = stage["$lookup"]
            from_coll = colls[l["from"]]
            new_data = []
            for d in data:
                local_val = resolve_field(d, l["localField"])
                matches = []
                for f in from_coll:
                    time.sleep(0.00005)
                    if resolve_field(f, l["foreignField"]) == local_val:
                        matches.append(dict(f))
                new_d = dict(d)
                new_d[l["as"]] = matches
                new_data.append(new_d)
            data = new_data
        elif "$unwind" in stage:
            field = stage["$unwind"].lstrip("$")
            new_data = []
            for d in data:
                arr = resolve_field(d, field)
                if isinstance(arr, list):
                    for item in arr:
                        new_d = dict(d)
                        new_d[field] = item
                        new_data.append(new_d)
            data = new_data
        elif "$project" in stage:
            new_data = []
            for d in data:
                new_d = {}
                for k, v in stage["$project"].items():
                    if isinstance(v, str) and v.startswith("$"):
                        new_d[k] = resolve_field(d, v.lstrip("$"))
                    else:
                        new_d[k] = v
                new_data.append(new_d)
            data = new_data
    return data

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--nodes")
    parser.add_argument("--edges")
    parser.add_argument("--pipeline")
    parser.add_argument("--out")
    args = parser.parse_args()

    nodes = load_csv(args.nodes)
    edges = load_csv(args.edges)
    with open(args.pipeline) as f:
        pipeline = json.load(f)
    out_data = run_pipeline(nodes, edges, pipeline)
    with open(args.out, "w") as f:
        json.dump(out_data, f)

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/graph_engine

    # Create naive pipeline
    cat << 'EOF' > /home/user/naive_pipeline.json
[
  {
    "$lookup": {
      "from": "edges",
      "localField": "node_id",
      "foreignField": "source_id",
      "as": "outgoing_edges"
    }
  },
  {
    "$unwind": "$outgoing_edges"
  },
  {
    "$lookup": {
      "from": "nodes",
      "localField": "outgoing_edges.target_id",
      "foreignField": "node_id",
      "as": "target_node"
    }
  },
  {
    "$unwind": "$target_node"
  },
  {
    "$match": {
      "type": "Server",
      "region": "us-east",
      "outgoing_edges.relationship_type": "depends_on",
      "target_node.type": "Database",
      "target_node.status": "offline"
    }
  },
  {
    "$project": {
      "server_id": "$node_id",
      "database_id": "$target_node.node_id"
    }
  }
]
EOF

    # Generate data
    cat << 'EOF' > /tmp/gen_data.py
import csv
import random

random.seed(42)
nodes = []
for i in range(1, 401):
    if i <= 10:
        nodes.append({"node_id": f"n{i}", "type": "Server", "status": "online", "region": "us-east"})
    elif i <= 20:
        nodes.append({"node_id": f"n{i}", "type": "Database", "status": "offline", "region": "us-west"})
    else:
        nodes.append({"node_id": f"n{i}", "type": "Client", "status": "online", "region": "eu-central"})

edges = []
for i in range(1, 11):
    edges.append({"source_id": f"n{i}", "target_id": f"n{i+10}", "relationship_type": "depends_on", "weight": 1})

for i in range(400):
    edges.append({"source_id": f"n{random.randint(21, 400)}", "target_id": f"n{random.randint(21, 400)}", "relationship_type": "connected_to", "weight": random.randint(1, 5)})

with open("/home/user/data/nodes.csv", "w") as f:
    writer = csv.DictWriter(f, fieldnames=["node_id", "type", "status", "region"])
    writer.writeheader()
    writer.writerows(nodes)

with open("/home/user/data/edges.csv", "w") as f:
    writer = csv.DictWriter(f, fieldnames=["source_id", "target_id", "relationship_type", "weight"])
    writer.writeheader()
    writer.writerows(edges)
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    chmod -R 777 /home/user
