import sys
import json
import argparse
from collections import deque

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--graph', required=True)
    parser.add_argument('--start', required=True)
    args = parser.parse_args()

    graph = json.loads(args.graph)
    start = args.start

    distances = {}
    queue = deque([(start, 0)])

    if start in graph:
        distances[start] = 0

    while queue:
        curr, dist = queue.popleft()
        for neighbor in graph.get(curr, []):
            neighbor = str(neighbor)
            if neighbor not in distances:
                distances[neighbor] = dist + 1
                queue.append((neighbor, dist + 1))

    # F = 123, F % 10 = 3
    filtered = [(n, d) for n, d in distances.items() if d <= 3]
    filtered.sort(key=lambda x: (-x[1], x[0]))

    res = ",".join([x[0] for x in filtered])
    print(res)

if __name__ == '__main__':
    main()
