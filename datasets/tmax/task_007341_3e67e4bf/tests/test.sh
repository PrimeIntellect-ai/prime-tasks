#!/bin/bash
set -e
mkdir -p /logs/verifier

BACKUP=""
cleanup() {
    if [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
        cp "$BACKUP" /home/user/plugin_manager/edges.txt
        rm -f "$BACKUP"
    fi
}
trap cleanup EXIT

run_verification() {
    PROJECT=/home/user/plugin_manager
    OUTPUT=/home/user/load_order.txt

    test -d "$PROJECT" || return 1
    test -f "$PROJECT/src/main.rs" && test ! -L "$PROJECT/src/main.rs" || return 1
    test -s "$PROJECT/src/main.rs" || return 1
    test -f "$PROJECT/src/libdeps.c" && test ! -L "$PROJECT/src/libdeps.c" || return 1
    test -s "$PROJECT/src/libdeps.c" || return 1
    test -f "$PROJECT/edges.txt" || return 1

    BACKUP=$(mktemp)
    cp "$PROJECT/edges.txt" "$BACKUP" || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import heapq
from collections import defaultdict

def compute_expected_order(edges_file):
    adj = defaultdict(list)
    indegree = defaultdict(int)
    nodes = set()

    with open(edges_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            u, v = map(int, line.split())
            adj[v].append(u)
            indegree[u] += 1
            nodes.add(u)
            nodes.add(v)

    queue = []
    for node in nodes:
        if indegree[node] == 0:
            heapq.heappush(queue, node)

    result = []
    while queue:
        curr = heapq.heappop(queue)
        result.append(curr)
        for neighbor in adj[curr]:
            indegree[neighbor] -= 1
            if indegree[neighbor] == 0:
                heapq.heappush(queue, neighbor)

    return result

def test_load_order_correctness():
    output_path = "/home/user/load_order.txt"
    edges_path = "/home/user/plugin_manager/edges.txt"

    assert os.path.exists(edges_path), f"Edges file {edges_path} is missing."
    assert os.path.exists(output_path), (
        f"{output_path} does not exist. The Rust program likely did not run, "
        "failed to compile, or failed to write the output file."
    )

    expected_order = compute_expected_order(edges_path)
    expected_str = " ".join(map(str, expected_order))

    with open(output_path, 'r') as f:
        actual_str = f.read().strip()

    assert actual_str == expected_str, (
        f"The plugin load order in {output_path} is incorrect.\n"
        f"Expected: '{expected_str}'\n"
        f"Actual:   '{actual_str}'\n"
        "Ensure you are performing a topological sort and always picking the "
        "smallest available plugin ID when breaking ties."
    )
TEST_EOF

    # Preserve the original assertion that the agent produced the requested file
    # for the image's supplied edges before verification began.
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    # Exercise the submitted C parser directly under AddressSanitizer with enough
    # pairs to force repeated growth of its allocation.
    cat << 'C_EOF' > /tmp/check_libdeps.c
#include <stdio.h>
#include <stdlib.h>

int *parse_deps(const char *filename, int *out_count);
void free_deps(int *edges);

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    int count = -1;
    int *edges = parse_deps(argv[1], &count);
    if (!edges || count < 0) return 3;

    FILE *f = fopen(argv[1], "r");
    if (!f) return 4;
    int u, v, i = 0;
    while (fscanf(f, "%d %d", &u, &v) == 2) {
        if (i >= count || edges[2 * i] != u || edges[2 * i + 1] != v) {
            fclose(f);
            free_deps(edges);
            return 5;
        }
        i++;
    }
    fclose(f);
    if (i != count) {
        free_deps(edges);
        return 6;
    }
    free_deps(edges);
    return 0;
}
C_EOF

    python3 - << 'PY_EOF'
with open('/tmp/large_edges.txt', 'w') as f:
    for i in range(1, 20001):
        f.write(f"{i + 1} {i}\n")
PY_EOF

    gcc -std=c11 -O0 -g -fsanitize=address -fno-omit-frame-pointer \
        /tmp/check_libdeps.c "$PROJECT/src/libdeps.c" -o /tmp/check_libdeps || return 1
    ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 /tmp/check_libdeps /tmp/large_edges.txt || return 1

    # Remove any stale artifact, compile the submitted Rust/C project, and require
    # the resulting application to solve several verifier-selected graphs.
    (cd "$PROJECT" && cargo clean && cargo build) || return 1
    test -x "$PROJECT/target/debug/plugin_manager" || return 1

    cat << 'PY_EOF' > /tmp/exercise_plugin_manager.py
import heapq
import os
import subprocess
from collections import defaultdict

project = "/home/user/plugin_manager"
edges_path = os.path.join(project, "edges.txt")
output_path = "/home/user/load_order.txt"
binary = os.path.join(project, "target", "debug", "plugin_manager")

def expected_order(edges):
    adj = defaultdict(list)
    indegree = defaultdict(int)
    nodes = set()
    for a, b in edges:
        adj[b].append(a)
        indegree[a] += 1
        nodes.add(a)
        nodes.add(b)
    ready = [n for n in nodes if indegree[n] == 0]
    heapq.heapify(ready)
    result = []
    while ready:
        node = heapq.heappop(ready)
        result.append(node)
        for nxt in adj[node]:
            indegree[nxt] -= 1
            if indegree[nxt] == 0:
                heapq.heappush(ready, nxt)
    assert len(result) == len(nodes)
    return " ".join(map(str, result))

def run_case(name, edges):
    with open(edges_path, "w") as f:
        for a, b in edges:
            f.write(f"{a} {b}\n")
    try:
        os.remove(output_path)
    except FileNotFoundError:
        pass
    proc = subprocess.run([binary], cwd=project, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=20)
    assert proc.returncode == 0, (
        f"application failed for {name}: stdout={proc.stdout!r}, "
        f"stderr={proc.stderr!r}"
    )
    assert os.path.isfile(output_path), f"application did not create output for {name}"
    with open(output_path) as f:
        actual = f.read().strip()
    expected = expected_order(edges)
    assert actual == expected, (
        f"wrong order for {name}: expected {expected!r}, got {actual!r}"
    )

cases = [
    ("tie_breaking", [(8, 3), (9, 3), (5, 1), (5, 2),
                      (7, 2), (10, 8), (10, 9)]),
    ("sparse_ids", [(101, 4), (55, 4), (77, 12), (101, 55),
                    (88, 12), (200, 77), (200, 88), (55, 12)]),
    ("interleaved_constraints", [(30, 20), (30, 10), (20, 3),
                                  (40, 3), (50, 20), (50, 40),
                                  (60, 10), (70, 60), (70, 50)]),
]
for name, edges in cases:
    run_case(name, edges)

large = []
for a in range(2, 901):
    large.append((a, a - 1))
    if a > 8:
        large.append((a, a - 7))
    if a > 20:
        large.append((a, a // 2))
run_case("large_configuration", large)
PY_EOF

    python3 /tmp/exercise_plugin_manager.py || return 1

    # Restore the supplied graph, execute the freshly built application on it,
    # and re-run the original correctness assertion.
    cp "$BACKUP" "$PROJECT/edges.txt" || return 1
    rm -f "$OUTPUT"
    (cd "$PROJECT" && ./target/debug/plugin_manager) || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1
}

if run_verification; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
