import sys
from collections import deque

edges = [
    ("LOBBY", "HALL_1"), ("HALL_1", "SERVER_ROOM"), ("HALL_1", "CAFETARIA"),
    ("CAFETARIA", "PATIO"), ("LOBBY", "HALL_2"), ("HALL_2", "HR_OFFICE"),
    ("HR_OFFICE", "EXEC_SUITE"), ("SERVER_ROOM", "BACK_ALLEY"),
    ("HALL_2", "IT_STORAGE"), ("IT_STORAGE", "SERVER_ROOM"),
    ("PATIO", "SMOKING_AREA"), ("EXEC_SUITE", "BALCONY"),
    ("LOBBY", "SECURITY_DESK"), ("SECURITY_DESK", "CAMERA_ROOM"),
    ("CAMERA_ROOM", "SERVER_ROOM")
]

graph = {}
for u, v in edges:
    graph.setdefault(u, []).append(v)
    graph.setdefault(v, []).append(u)

def bfs(start, end):
    if start not in graph or end not in graph: return "NO_PATH"
    if start == end: return start
    queue = deque([[start]])
    visited = set([start])

    while queue:
        path = queue.popleft()
        node = path[-1]

        # Sort neighbors to ensure deterministic shortest path choice for fuzz equivalence
        for neighbor in sorted(graph.get(node, [])):
            if neighbor == end:
                return ",".join(path + [neighbor])
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append(path + [neighbor])
    return "NO_PATH"

if __name__ == "__main__":
    if len(sys.argv) != 3: sys.exit(1)
    print(bfs(sys.argv[1], sys.argv[2]))
