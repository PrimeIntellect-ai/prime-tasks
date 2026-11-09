import sys, json

COSTS = {
    "INDEX_SCAN": 10,
    "TABLE_SCAN": 50,
    "HASH_JOIN": 20,
    "NESTED_LOOP": 100,
    "GRAPH_TRAVERSAL": 5
}

def calc_cost(node):
    if not isinstance(node, dict): return 0
    cost = COSTS.get(node.get("operation", ""), 0)
    if "left" in node: cost += calc_cost(node["left"])
    if "right" in node: cost += calc_cost(node["right"])
    if "children" in node and isinstance(node["children"], list):
        for child in node["children"]:
            cost += calc_cost(child)
    return cost

if __name__ == "__main__":
    try:
        data = json.loads(sys.stdin.read())
        print(calc_cost(data))
    except Exception as e:
        print(0)
