import sys
import csv
from collections import deque

def main():
    if len(sys.argv) != 3:
        sys.exit(1)

    csv_file = sys.argv[1]
    target = sys.argv[2]

    adj = {}
    with open(csv_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            u = row['tx']
            v = row['waiting_for']
            if u not in adj: adj[u] = []
            if v not in adj: adj[v] = []
            adj[u].append(v)

    if target not in adj:
        print("NO_DEADLOCK")
        return

    q = deque([(target, [target])])
    visited = {target: 0}

    shortest_cycles = []
    min_len = float('inf')

    while q:
        curr, path = q.popleft()

        if len(path) > min_len:
            break

        for nxt in adj.get(curr, []):
            if nxt == target:
                cycle_len = len(path)
                if cycle_len < min_len:
                    min_len = cycle_len
                    shortest_cycles = [path + [target]]
                elif cycle_len == min_len:
                    shortest_cycles.append(path + [target])
            elif nxt not in visited or visited[nxt] == len(path):
                visited[nxt] = len(path)
                q.append((nxt, path + [nxt]))

    if not shortest_cycles:
        print("NO_DEADLOCK")
    else:
        shortest_cycles.sort()
        print(",".join(shortest_cycles[0]))

if __name__ == "__main__":
    main()
