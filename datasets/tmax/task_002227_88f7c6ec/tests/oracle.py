import sys
import json
from collections import defaultdict

def solve():
    N = 7
    try:
        data = json.loads(sys.stdin.read().strip())
    except:
        return

    nodes = {n['id']: n for n in data.get('nodes', [])}
    adj = defaultdict(list)
    for e in data.get('edges', []):
        adj[e['source']].append(e['target'])
        adj[e['target']].append(e['source'])

    valid_users = set()
    for node_id, node in nodes.items():
        if node.get('type') == 'User':
            for neighbor_id in adj[node_id]:
                neighbor = nodes.get(neighbor_id)
                if neighbor and neighbor.get('type') == 'Product' and neighbor.get('price', 0) > N:
                    valid_users.add(node_id)
                    break

    sorted_users = sorted(list(valid_users), reverse=True)[:5]
    if sorted_users:
        print(",".join(sorted_users))
    else:
        print()

if __name__ == "__main__":
    solve()
