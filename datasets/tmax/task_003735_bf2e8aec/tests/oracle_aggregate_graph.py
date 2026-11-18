#!/usr/bin/env python3
import sys
import csv
from collections import defaultdict

def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    nodes = {}
    children = defaultdict(list)

    with open(sys.argv[1], 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            nid = int(row['node_id'])
            pid = int(row['parent_id']) if row['parent_id'] and row['parent_id'] != '0' else 0
            val = int(row['metric_value'])
            nodes[nid] = val
            if pid != 0:
                children[pid].append(nid)

    memo = {}
    def get_sum(n):
        if n in memo: return memo[n]
        s = nodes.get(n, 0)
        for c in children[n]:
            s += get_sum(c)
        memo[n] = s
        return s

    print("node_id,total_metric")
    for nid in sorted(nodes.keys()):
        print(f"{nid},{get_sum(nid)}")

if __name__ == "__main__":
    main()
