import sqlite3
import time

conn = sqlite3.connect('/app/network.db')
c = conn.cursor()

# Slow query
c.execute("SELECT r.source, r.target, c.cost FROM raw_links r JOIN link_costs c ON r.link_id = c.link_id")
edges = c.fetchall()

# Artificial delay to simulate an unoptimized implementation and ensure 5x speedup is possible
time.sleep(2.0)

dist = {1050: 0}
for _ in range(5):
    for u, v, cost in edges:
        if u in dist:
            if v not in dist or dist[u] + cost < dist[v]:
                dist[v] = dist[u] + cost

print(dist.get(8920, -1))
