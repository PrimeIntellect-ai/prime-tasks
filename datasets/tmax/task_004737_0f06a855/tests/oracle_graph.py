import sys
import json
import cv2

def main():
    start_node = int(sys.argv[1])
    weight_limit = int(sys.argv[2])

    cap = cv2.VideoCapture('/app/data_stream.mp4')
    edges = []
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        # frame is BGR
        b, g, r = frame[0, 0]
        edges.append((int(r), int(g), int(b)))
    cap.release()

    # Filter edges
    filtered_edges = [e for e in edges if e[2] <= weight_limit]

    # Adjacency list for filtered graph
    adj = {}
    for r, g, b in filtered_edges:
        if r not in adj: adj[r] = []
        if g not in adj: adj[g] = []
        adj[r].append(g)

    if start_node not in adj:
        print(json.dumps({"reachable_count": 1, "max_out_node": start_node}))
        return

    # BFS
    reachable = set([start_node])
    queue = [start_node]
    while queue:
        curr = queue.pop(0)
        for neighbor in adj.get(curr, []):
            if neighbor not in reachable:
                reachable.add(neighbor)
                queue.append(neighbor)

    # Calculate out-degrees in filtered graph for reachable nodes only
    best_node = min(reachable)
    max_out = -1

    for node in reachable:
        out_deg = len(adj.get(node, []))
        if out_deg > max_out:
            max_out = out_deg
            best_node = node
        elif out_deg == max_out:
            if node < best_node:
                best_node = node

    print(json.dumps({"reachable_count": len(reachable), "max_out_node": best_node}))

if __name__ == "__main__":
    main()
