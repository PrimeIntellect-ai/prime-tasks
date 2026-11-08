import sys
import json
import heapq

def solve(input_json_str):
    data = json.loads(input_json_str)
    tasks = data['tasks']
    dependencies = data['dependencies']
    max_cost = data['max_cost_per_batch']

    adj = {t: [] for t in tasks}
    in_degree = {t: 0 for t in tasks}

    for u, v in dependencies:
        adj[u].append(v)
        in_degree[v] += 1

    pq = []
    for t in tasks:
        if in_degree[t] == 0:
            heapq.heappush(pq, t)

    sorted_tasks = []
    while pq:
        u = heapq.heappop(pq)
        sorted_tasks.append(u)
        for v in adj[u]:
            in_degree[v] -= 1
            if in_degree[v] == 0:
                heapq.heappush(pq, v)

    batches = []
    current_batch = []
    current_cost = 0

    for t in sorted_tasks:
        cost = tasks[t]['cost']
        if current_cost + cost > max_cost and current_batch:
            batches.append(current_batch)
            current_batch = [t]
            current_cost = cost
        else:
            current_batch.append(t)
            current_cost += cost

    if current_batch:
        batches.append(current_batch)

    print(json.dumps(batches))

if __name__ == '__main__':
    solve(sys.argv[1])
