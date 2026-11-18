#!/usr/bin/env python3
import sys, json

def solve():
    if len(sys.argv) < 2: return
    nodes = {}
    with open(sys.argv[1], 'r') as f:
        for line in f:
            if not line.strip(): continue
            d = json.loads(line)
            n_id = d['X_Z9']
            nodes[n_id] = {
                'node_id': n_id,
                'parent_id': d.get('P_K2'),
                'backup_size': d['S_M1'],
                'timestamp': d['T_D5']
            }

    # Calc restore size
    memo = {}
    def get_size(nid):
        if nid not in nodes: return 0
        if nid in memo: return memo[nid]
        p = nodes[nid]['parent_id']
        sz = nodes[nid]['backup_size']
        if p and p in nodes:
            sz += get_size(p)
        memo[nid] = sz
        return sz

    for nid in nodes:
        get_size(nid)

    # Calc window rank
    partitions = {}
    for nid, data in nodes.items():
        p = data['parent_id']
        if p not in partitions: partitions[p] = []
        partitions[p].append(data)

    ranks = {}
    for p, items in partitions.items():
        items.sort(key=lambda x: x['timestamp'], reverse=True)
        for i, item in enumerate(items):
            ranks[item['node_id']] = i + 1

    out = []
    for nid in sorted(nodes.keys()):
        out.append(json.dumps({
            "node_id": nid,
            "total_restore_size": memo[nid],
            "sibling_rank": ranks[nid]
        }))
    print("\n".join(out))

if __name__ == '__main__':
    solve()
