#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import uuid

SCRIPT_PATH = "/home/user/build_router.sh"
LOG_PATH = "/home/user/build_order.log"
DEPS_PATH = "/home/user/deps.txt"


def parse_graph(path):
    graph = {}
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(":", 1)
            target = parts[0].strip()
            deps = parts[1].strip().split() if len(parts) > 1 else []
            graph[target] = deps
    return graph


def expected_lines(graph, target):
    visited = set()
    order = []

    def dfs(node):
        if node in visited:
            return
        visited.add(node)
        for dep in graph.get(node, []):
            dfs(dep)
        order.append(node)

    dfs(target)
    return [f"[BUILD] {node}" for node in order]


def run_and_check(url, expected):
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    result = subprocess.run(
        [SCRIPT_PATH, url], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Script exited with non-zero status code: {result.returncode}\n"
        f"Stderr: {result.stderr}"
    )
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} was not created."

    with open(LOG_PATH, "r") as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected, (
        f"Build order in {LOG_PATH} is incorrect.\n"
        f"Expected: {expected}\nActual: {actual}"
    )


def test_build_router_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_build_router_execution_and_output():
    # Preserve the original verifier's assertion against the installed graph.
    assert os.path.isfile(DEPS_PATH), f"{DEPS_PATH} is missing."
    graph = parse_graph(DEPS_PATH)
    run_and_check(
        "/build/frontend?dryrun=1",
        expected_lines(graph, "frontend"),
    )


def test_dynamic_routing_and_dependency_resolution():
    # Runtime-random names prevent a fixed, precomputed frontend order from passing.
    token = uuid.uuid4().hex
    names = {key: f"{key}_{token}" for key in (
        "root", "left", "right", "shared", "branch", "base", "leaf1", "leaf2"
    )}
    graph = {
        names["root"]: [names["left"], names["right"]],
        names["left"]: [names["shared"], names["leaf1"]],
        names["right"]: [names["shared"], names["branch"]],
        names["shared"]: [names["base"]],
        names["branch"]: [names["base"], names["leaf2"]],
        names["base"]: [],
        names["leaf1"]: [],
        names["leaf2"]: [],
    }

    with open(DEPS_PATH, "rb") as f:
        original_deps = f.read()

    try:
        with open(DEPS_PATH, "w") as f:
            for target, deps in graph.items():
                f.write(f"{target}: {' '.join(deps)}\n")

        # Query parameters must be ignored, shared dependencies must be emitted once,
        # and dependencies must follow left-to-right post-order traversal.
        run_and_check(
            f"/build/{names['root']}?env={uuid.uuid4().hex}&dryrun=1",
            expected_lines(graph, names["root"]),
        )

        # A different requested target verifies that the URL argument is actually used.
        run_and_check(
            f"/build/{names['branch']}",
            expected_lines(graph, names["branch"]),
        )
    finally:
        with open(DEPS_PATH, "wb") as f:
            f.write(original_deps)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
