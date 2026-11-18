#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import heapq
import os
import pwd
import random
import secrets
import subprocess
import tempfile

SOURCE = "/home/user/route_solver.c"
EXECUTABLE = "/home/user/route_solver"
CSV_PATH = "/home/user/hub_transit_data.csv"
LOG_PATH = "/home/user/shortest_path.log"

ORIGINAL_CSV = """source_hub,destination_hub,transit_time
Seattle,Denver,10
Denver,Chicago,5
Seattle,Chicago,20
Chicago,NewYork,10
Denver,NewYork,20
NewYork,Miami,5
Seattle,SanFrancisco,8
SanFrancisco,LosAngeles,6
LosAngeles,Miami,25
Chicago,Dallas,12
Dallas,Miami,8
"""

ORIGINAL_EXPECTED = (
    "Shortest Transit Time: 30\n"
    "Route: Seattle -> Denver -> Chicago -> NewYork -> Miami"
)


def normalized_log():
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} is missing."
    assert os.path.isfile(LOG_PATH), f"Path {LOG_PATH} exists but is not a file."
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()
    return "\n".join(line.strip() for line in content.splitlines() if line.strip())


def assert_log(expected):
    actual = normalized_log()
    expected_normalized = "\n".join(line.strip() for line in expected.splitlines())
    assert actual == expected_normalized, (
        "Log file content does not match expected output.\n"
        f"Expected:\n{expected}\nActual:\n{actual}"
    )


def write_csv(edges):
    with open(CSV_PATH, "w", encoding="utf-8", newline="") as f:
        f.write("source_hub,destination_hub,transit_time\n")
        for source, destination, weight in edges:
            f.write(f"{source},{destination},{weight}\n")


def oracle(edges):
    graph = {}
    for source, destination, weight in edges:
        graph.setdefault(source, []).append((destination, weight))
        graph.setdefault(destination, [])

    distances = {"Seattle": 0}
    previous = {}
    queue = [(0, "Seattle")]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances.get(node):
            continue
        if node == "Miami":
            break
        for neighbor, weight in graph.get(node, []):
            candidate = distance + weight
            if candidate < distances.get(neighbor, 10**30):
                distances[neighbor] = candidate
                previous[neighbor] = node
                heapq.heappush(queue, (candidate, neighbor))

    assert "Miami" in distances, "Verifier generated an unreachable graph"
    path = ["Miami"]
    while path[-1] != "Seattle":
        path.append(previous[path[-1]])
    path.reverse()
    return (
        f"Shortest Transit Time: {distances['Miami']}\n"
        f"Route: {' -> '.join(path)}"
    )


def run_solver(path, edges, expected):
    write_csv(edges)
    if os.path.lexists(LOG_PATH):
        os.unlink(LOG_PATH)

    user = pwd.getpwnam("user")
    def demote():
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    result = subprocess.run(
        [path],
        cwd="/home/user",
        env={**os.environ, "HOME": "/home/user"},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=8,
        preexec_fn=demote,
    )
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert_log(expected)


def parse_original_edges():
    edges = []
    for line in ORIGINAL_CSV.strip().splitlines()[1:]:
        source, destination, weight = line.split(",")
        edges.append((source, destination, int(weight)))
    return edges


def make_random_case(rng):
    tag = secrets.token_hex(5)
    hubs = [f"Hub_{tag}_{i}" for i in range(5)]
    weights = [rng.randint(2, 12) for _ in range(4)]
    chain = ["Seattle", hubs[0], hubs[1], hubs[2], "Miami"]
    edges = [
        (chain[i], chain[i + 1], weights[i])
        for i in range(len(chain) - 1)
    ]
    total = sum(weights)
    edges.extend([
        ("Seattle", "Miami", total + rng.randint(30, 70)),
        ("Seattle", hubs[3], total + 10),
        (hubs[3], "Miami", total + 10),
        (hubs[0], hubs[4], total + 20),
        (hubs[4], "Miami", total + 20),
        (hubs[2], hubs[0], rng.randint(1, 9)),
        ("Miami", "Seattle", rng.randint(1, 9)),
    ])
    rng.shuffle(edges)
    return edges


def make_capacity_case(rng):
    tag = secrets.token_hex(5)
    intermediates = [f"Node_{tag}_{i:02d}" for i in range(98)]
    all_nodes = ["Seattle", "Miami"] + intermediates
    chain = ["Seattle"] + intermediates[:18] + ["Miami"]

    edge_map = {}
    for source, destination in zip(chain, chain[1:]):
        edge_map[(source, destination)] = 1

    # Ensure all 100 hubs occur while keeping every non-planted route expensive.
    for node in intermediates:
        edge_map.setdefault(("Seattle", node), 2000 + rng.randint(0, 500))
        edge_map.setdefault((node, "Miami"), 2000 + rng.randint(0, 500))

    candidates = [
        (source, destination)
        for source in all_nodes
        for destination in all_nodes
        if source != destination and (source, destination) not in edge_map
    ]
    rng.shuffle(candidates)
    for source, destination in candidates:
        if len(edge_map) >= 1000:
            break
        edge_map[(source, destination)] = rng.randint(3000, 9000)

    assert len(edge_map) == 1000
    edges = [(source, destination, weight)
             for (source, destination), weight in edge_map.items()]
    rng.shuffle(edges)
    return edges


# Preserve all original existence, type, executable, and initial-output assertions.
assert os.path.exists(SOURCE), f"C source file {SOURCE} is missing."
assert os.path.isfile(SOURCE), f"Path {SOURCE} exists but is not a file."
assert os.path.exists(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
assert os.path.isfile(EXECUTABLE), f"Path {EXECUTABLE} exists but is not a file."
assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
assert_log(ORIGINAL_EXPECTED)

# A gcc-produced native executable must be an ELF file, not an arbitrary script.
with open(EXECUTABLE, "rb") as f:
    assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not an ELF executable."

original_edges = parse_original_edges()
original_csv_bytes = open(CSV_PATH, "rb").read()
compiled_fd, compiled_path = tempfile.mkstemp(prefix="route_solver_rebuilt_", dir="/tmp")
os.close(compiled_fd)
os.unlink(compiled_path)

try:
    compile_result = subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", compiled_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        "route_solver.c does not compile successfully with gcc.\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )

    rng = random.SystemRandom()
    cases = [
        (original_edges, ORIGINAL_EXPECTED),
        (make_random_case(rng), None),
        (make_random_case(rng), None),
        (make_capacity_case(rng), None),
    ]

    # Exercise both the submitted executable and a fresh build of the submitted C source.
    for solver in (EXECUTABLE, compiled_path):
        for edges, fixed_expected in cases:
            expected = fixed_expected if fixed_expected is not None else oracle(edges)
            run_solver(solver, edges, expected)

    # Leave the requested artifact's log corresponding to the supplied input dataset.
    run_solver(EXECUTABLE, original_edges, ORIGINAL_EXPECTED)
finally:
    with open(CSV_PATH, "wb") as f:
        f.write(original_csv_bytes)
    if os.path.exists(compiled_path):
        os.unlink(compiled_path)
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
