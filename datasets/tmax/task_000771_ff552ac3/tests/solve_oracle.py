#!/usr/bin/env python3
import sys, json, csv
def solve(json_path):
    with open(json_path) as f:
        data = json.load(f)
    nodes = {n['id']: n['value'] for n in data['nodes']}
    edges = {}
    for e in data['edges']:
        edges.setdefault(e['parent'], []).append(e['child'])

    memo = {}
    def dfs(node_id):
        if node_id in memo: return memo[node_id]
        total = nodes.get(node_id, 0)
        for child in edges.get(node_id, []):
            total += dfs(child)
        memo[node_id] = total
        return total

    results = []
    for n in sorted(nodes.keys()):
        results.append([n, dfs(n)])

    writer = csv.writer(sys.stdout)
    writer.writerow(["id", "total_value"])
    writer.writerows(results)

if __name__ == "__main__":
    solve(sys.argv[1])
