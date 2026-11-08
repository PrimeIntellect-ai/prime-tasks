#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import re
import secrets
import shutil
import subprocess

SCRIPT = "/home/user/generate_routes.sh"
MODULES = "/home/user/modules"
CONF = "/home/user/routes.conf"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."

    with open(SCRIPT, "rb") as f:
        first_line = f.readline(256).decode("utf-8", errors="replace").strip()
    assert re.match(r"^#!.*(?:/|\b)bash(?:\s|$)", first_line), (
        f"{SCRIPT} must be a Bash script with a Bash shebang."
    )


def install_graph(graph):
    shutil.rmtree(MODULES, ignore_errors=True)
    os.makedirs(MODULES)
    for module, dependencies in graph.items():
        module_dir = os.path.join(MODULES, module)
        os.makedirs(module_dir)
        with open(os.path.join(module_dir, "deps.txt"), "w") as f:
            for dependency in dependencies:
                f.write(dependency + "\n")

    if os.path.lexists(CONF):
        os.unlink(CONF)
    with open(CONF, "w") as f:
        f.write("stale output that must be replaced\n")


def expected_order(graph):
    indegree = {module: len(dependencies) for module, dependencies in graph.items()}
    dependents = {module: [] for module in graph}
    for module, dependencies in graph.items():
        for dependency in dependencies:
            assert dependency in graph
            dependents[dependency].append(module)

    ready = [module for module, degree in indegree.items() if degree == 0]
    heapq.heapify(ready)
    result = []
    while ready:
        module = heapq.heappop(ready)
        result.append(module)
        for dependent in dependents[module]:
            indegree[dependent] -= 1
            if indegree[dependent] == 0:
                heapq.heappush(ready, dependent)

    assert len(result) == len(graph)
    return result


def run_and_check(graph):
    install_graph(graph)
    result = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{SCRIPT} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(CONF), f"Configuration file {CONF} does not exist."

    expected_lines = [
        f"ProxyPass /{module} http://localhost:8080/{module}"
        for module in expected_order(graph)
    ]
    with open(CONF, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == expected_lines, (
        f"Contents of {CONF} do not match the expected topological sort output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def test_routes_conf_content():
    graph = {
        "core": [],
        "auth": ["core"],
        "billing": ["auth", "core"],
        "api": ["auth", "billing"],
        "frontend": ["api", "core"],
    }
    run_and_check(graph)


def test_dependency_resolution_on_unseen_graphs():
    # Random names prevent a submission from passing by hardcoding verifier output.
    names = [f"mod_{secrets.token_hex(5)}" for _ in range(7)]

    # All modules are initially available, directly exercising alphabetical ties.
    run_and_check({name: [] for name in names})

    # A nontrivial DAG has ties both initially and after dependencies are resolved.
    a, b, c, d, e, f, g = names
    graph = {
        a: [],
        b: [],
        c: [a],
        d: [a],
        e: [b, c],
        f: [c, d],
        g: [e, f],
    }
    run_and_check(graph)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
