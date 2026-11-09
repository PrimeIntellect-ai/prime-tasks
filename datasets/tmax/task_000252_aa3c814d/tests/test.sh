#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import heapq
import os
import random
import secrets
import shutil
import subprocess
import tempfile
import time

FAST = "/home/user/fast_router"
LEGACY = "/app/legacy_router"

assert os.path.exists(FAST), f"Fast router binary is missing at {FAST}"
assert os.path.isfile(FAST), f"{FAST} is not a file"
assert os.access(FAST, os.X_OK), f"Fast router binary at {FAST} is not executable"

rng = random.SystemRandom()
tmpdir = tempfile.mkdtemp(prefix="router_verify_")
cases = []


def write_case(name, edges, start, end, expected):
    path = os.path.join(tmpdir, name + ".txt")
    rng.shuffle(edges)
    with open(path, "w", encoding="utf-8") as f:
        for link, u, v, lat, jit, drop in edges:
            f.write(f"{link} {u} {v} {lat} {jit} {drop}\n")
    cases.append((path, start, end, expected))


def expected_output(path, cost):
    return "Path: " + " -> ".join(path) + f"\nTotal Cost: {cost}"


# Random tree cases have one cheap route between every pair. Expensive extra
# links exercise parsing and cycles without introducing shortest-path ties.
for case_no in range(6):
    token = secrets.token_hex(5)
    n = rng.randint(25, 45)
    nodes = [f"N_{token}_{i}_{secrets.token_hex(2)}" for i in range(n)]
    tree_adj = [[] for _ in range(n)]
    edges = []
    edge_no = 0
    for i in range(1, n):
        p = rng.randrange(i)
        lat = rng.randint(1, 30)
        jit = rng.randint(0, 20)
        drop = 0
        cost = lat + 2 * jit + 100 * drop
        edges.append((f"L_{token}_{edge_no}", nodes[p], nodes[i], lat, jit, drop))
        edge_no += 1
        tree_adj[p].append((i, cost))
        tree_adj[i].append((p, cost))

    used = set()
    while len(edges) < n + rng.randint(30, 70):
        u = rng.randrange(n)
        v = rng.randrange(n)
        if u == v:
            continue
        key = tuple(sorted((u, v)))
        if key in used:
            continue
        used.add(key)
        edges.append((f"L_{token}_{edge_no}", nodes[u], nodes[v],
                      rng.randint(1, 40), rng.randint(0, 20), 100))
        edge_no += 1

    s = rng.randrange(n)
    t = rng.randrange(n)
    while t == s:
        t = rng.randrange(n)

    parent = {s: (-1, 0)}
    stack = [s]
    while stack:
        u = stack.pop()
        for v, cost in tree_adj[u]:
            if v not in parent:
                parent[v] = (u, cost)
                stack.append(v)
    route = []
    total = 0
    cur = t
    while cur != -1:
        route.append(nodes[cur])
        prev, cost = parent[cur]
        total += cost
        cur = prev
    route.reverse()
    write_case(f"tree_{case_no}_{token}", edges, nodes[s], nodes[t],
               expected_output(route, total))

# Randomized diamond explicitly distinguishes latency, jitter, and drop-rate
# weighting while retaining a unique best route.
token = secrets.token_hex(6)
s, a, b, t = [f"D_{token}_{x}" for x in "SABT"]
while True:
    ma = [(rng.randint(1, 60), rng.randint(0, 30), rng.randint(0, 6)) for _ in range(2)]
    mb = [(rng.randint(1, 60), rng.randint(0, 30), rng.randint(0, 6)) for _ in range(2)]
    ca = sum(lat + 2 * jit + 100 * drop for lat, jit, drop in ma)
    cb = sum(lat + 2 * jit + 100 * drop for lat, jit, drop in mb)
    if ca != cb:
        break
edges = [
    (f"L_{token}_0", s, a, *ma[0]),
    (f"L_{token}_1", a, t, *ma[1]),
    (f"L_{token}_2", s, b, *mb[0]),
    (f"L_{token}_3", b, t, *mb[1]),
]
if ca < cb:
    route, total = [s, a, t], ca
else:
    route, total = [s, b, t], cb
write_case(f"diamond_{token}", edges, s, t, expected_output(route, total))

# Disconnected randomized graph.
token = secrets.token_hex(6)
x = [f"X_{token}_{i}" for i in range(6)]
edges = [
    (f"L_{token}_0", x[0], x[1], rng.randint(1, 20), rng.randint(0, 9), rng.randint(0, 3)),
    (f"L_{token}_1", x[1], x[2], rng.randint(1, 20), rng.randint(0, 9), rng.randint(0, 3)),
    (f"L_{token}_2", x[3], x[4], rng.randint(1, 20), rng.randint(0, 9), rng.randint(0, 3)),
    (f"L_{token}_3", x[4], x[5], rng.randint(1, 20), rng.randint(0, 9), rng.randint(0, 3)),
]
write_case(f"disconnected_{token}", edges, x[0], x[5], "No path found")

# Large, freshly generated speed case. The direct edge is the unique shortest
# route; all remaining edges still have to be parsed and represented.
token = secrets.token_hex(8)
num_nodes = rng.randint(1800, 2200)
num_edges = rng.randint(9500, 10500)
nodes = [f"S_{token}_{i}_{secrets.token_hex(2)}" for i in range(num_nodes)]
start_i = rng.randrange(num_nodes)
end_i = rng.randrange(num_nodes)
while end_i == start_i:
    end_i = rng.randrange(num_nodes)
start_node, end_node = nodes[start_i], nodes[end_i]
speed_edges = [(f"L_{token}_0", start_node, end_node, 1, 0, 0)]
for i in range(num_nodes - 1):
    speed_edges.append((f"L_{token}_{len(speed_edges)}", nodes[i], nodes[i + 1],
                        rng.randint(1, 50), rng.randint(0, 20), 100))
while len(speed_edges) < num_edges:
    u = rng.randrange(num_nodes)
    v = rng.randrange(num_nodes)
    if u == v:
        v = (v + 1) % num_nodes
    speed_edges.append((f"L_{token}_{len(speed_edges)}", nodes[u], nodes[v],
                        rng.randint(1, 50), rng.randint(0, 20), 100))
speed_path = os.path.join(tmpdir, f"large_{token}.txt")
with open(speed_path, "w", encoding="utf-8") as f:
    for edge in speed_edges:
        f.write("{} {} {} {} {} {}\n".format(*edge))
speed_expected = expected_output([start_node, end_node], 1)

legacy_outputs = []
hidden_legacy = os.path.join(tmpdir, "legacy_router.hidden")
legacy_time = None
fast_time = None
moved = False
try:
    # Check independently derived answers against the legacy implementation.
    for path, start, end, expected in cases:
        out = subprocess.check_output([LEGACY, path, start, end], text=True, timeout=20)
        assert out.strip() == expected, "Legacy output disagrees with derived randomized answer"
        legacy_outputs.append(out)

    t0 = time.perf_counter()
    legacy_speed_out = subprocess.check_output(
        [LEGACY, speed_path, start_node, end_node], text=True, timeout=30)
    legacy_time = time.perf_counter() - t0
    assert legacy_speed_out.strip() == speed_expected

    # Remove the oracle's normal path while exercising the replacement, so a
    # wrapper that simply invokes /app/legacy_router cannot pass.
    os.replace(LEGACY, hidden_legacy)
    moved = True

    for (path, start, end, expected), legacy_out in zip(cases, legacy_outputs):
        out = subprocess.check_output([FAST, path, start, end], text=True, timeout=5)
        assert out.strip() == legacy_out.strip(), \
            "The output of fast_router does not match legacy_router exactly"
        assert out.strip() == expected

    t0 = time.perf_counter()
    fast_speed_out = subprocess.check_output(
        [FAST, speed_path, start_node, end_node], text=True, timeout=10)
    fast_time = time.perf_counter() - t0
    assert fast_speed_out.strip() == legacy_speed_out.strip(), \
        "The output of fast_router does not match legacy_router exactly"

    speedup = legacy_time / max(fast_time, 0.001)
    assert speedup >= 50.0, \
        f"Speedup is {speedup:.2f}x, which is less than the required 50.0x threshold"
finally:
    if moved and os.path.exists(hidden_legacy):
        os.replace(hidden_legacy, LEGACY)
    shutil.rmtree(tmpdir, ignore_errors=True)
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
