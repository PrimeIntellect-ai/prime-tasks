import sys
import json
from collections import defaultdict

def main():
    try:
        data = json.load(sys.stdin)
    except:
        print("[]")
        return

    exclude_type = "SYSTEM"
    max_weight = 800
    min_degree = 2

    nodes = defaultdict(lambda: {"degree": 0, "weight_sum": 0})

    for edge in data:
        if edge.get("type") == exclude_type:
            continue
        weight = edge.get("weight", 0)
        if weight > max_weight:
            continue

        src = edge["src"]
        dst = edge["dst"]

        nodes[src]["degree"] += 1
        nodes[src]["weight_sum"] += weight

        nodes[dst]["degree"] += 1
        nodes[dst]["weight_sum"] += weight

    result = []
    for node_id, stats in nodes.items():
        if stats["degree"] >= min_degree:
            result.append({
                "node": node_id,
                "degree": stats["degree"],
                "weight_sum": stats["weight_sum"]
            })

    result.sort(key=lambda x: (-x["degree"], x["node"]))
    print(json.dumps(result))

if __name__ == "__main__":
    main()
