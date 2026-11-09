#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_service_resolver.py
import importlib.util
import json
import os
import resource
import secrets
import subprocess
import sys

SCRIPT = "/home/user/service_resolver.py"
DEPS = "/home/user/dependencies.json"
OUTPUT = "/home/user/execution_order.txt"
LIMIT = 120 * 1024 * 1024
EXPECTED_ORIGINAL = "Database,AuthService,Cache,UserService,API_Gateway,Frontend,Logging,Metrics"


def child_limit():
    resource.setrlimit(resource.RLIMIT_AS, (LIMIT, LIMIT))


def run_resolver():
    if os.path.lexists(OUTPUT):
        os.unlink(OUTPUT)
    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        preexec_fn=child_limit,
    )
    assert result.returncode == 0, (
        f"service_resolver.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"File missing after executing script: {OUTPUT}"
    with open(OUTPUT, "r") as f:
        return f.read().strip()


def expected_order(data):
    nodes = {}
    for service, dependencies in data.items():
        nodes.setdefault(service, [])
        for dependency in dependencies:
            nodes.setdefault(dependency, [])
            nodes[service].append(dependency)

    visited = set()
    temporary = set()
    order = []

    def visit(name):
        assert name not in temporary, "Verifier generated a cyclic graph"
        if name in visited:
            return
        temporary.add(name)
        for dependency in nodes[name]:
            visit(dependency)
        temporary.remove(name)
        visited.add(name)
        order.append(name)

    for name in sorted(nodes):
        if name not in visited:
            visit(name)
    return ",".join(order)


assert os.path.isfile(SCRIPT), f"File missing: {SCRIPT}"
with open(SCRIPT, "r") as f:
    source = f.read()
assert "self._mock_env_data = bytearray(10 * 1024 * 1024)" in source, (
    "The heavy state simulation (_mock_env_data) was removed or altered in "
    "service_resolver.py. You must fix the traversal logic itself."
)

# Execute against the supplied graph rather than trusting a pre-created output file.
actual = run_resolver()
assert actual == EXPECTED_ORIGINAL, (
    f"Content of {OUTPUT} is incorrect. Expected '{EXPECTED_ORIGINAL}', got '{actual}'."
)

# Exercise the executable on an unpredictable graph and derive its expected answer.
with open(DEPS, "rb") as f:
    original_dependencies = f.read()
try:
    prefix = "svc_" + secrets.token_hex(6) + "_"
    dynamic_data = {
        prefix + "A": [prefix + "C"],
        prefix + "B": [prefix + "C", prefix + "D"],
        prefix + "C": [prefix + "E"],
        prefix + "D": [],
        prefix + "E": [],
        prefix + "F": [prefix + "D"],
        prefix + "G": [],
    }
    with open(DEPS, "w") as f:
        json.dump(dynamic_data, f)
    expected = expected_order(dynamic_data)
    actual = run_resolver()
    assert actual == expected, (
        f"Resolver produced the wrong order for a generated dependency graph. "
        f"Expected '{expected}', got '{actual}'."
    )
finally:
    with open(DEPS, "wb") as f:
        f.write(original_dependencies)

# Inspect the real graph implementation in a separately memory-limited process.
probe = r'''
import importlib.util

path = "/home/user/service_resolver.py"
spec = importlib.util.spec_from_file_location("submitted_service_resolver", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

graph = module.DependencyGraph()
for name in ("zz", "aa", "mm"):
    graph.add_node(name)
graph.nodes["zz"].add_dependency(graph.nodes["aa"])

for node in graph.nodes.values():
    assert isinstance(node._mock_env_data, bytearray), "_mock_env_data is not a bytearray"
    assert len(node._mock_env_data) == 10 * 1024 * 1024, "_mock_env_data has the wrong size"

order = graph.resolve()
assert order == ["aa", "mm", "zz"], "resolve() did not preserve sorted node iteration"
assert graph.traversal_paths, "Traversal path logging was removed instead of repaired"

def contains_heavy(value, seen=None):
    if seen is None:
        seen = set()
    ident = id(value)
    if ident in seen:
        return False
    seen.add(ident)
    if isinstance(value, (module.ServiceNode, bytearray)):
        return True
    if isinstance(value, dict):
        return any(contains_heavy(k, seen) or contains_heavy(v, seen) for k, v in value.items())
    if isinstance(value, (list, tuple, set, frozenset)):
        return any(contains_heavy(item, seen) for item in value)
    return False

assert not contains_heavy(graph.traversal_paths), (
    "traversal_paths still persist heavy ServiceNode objects or their bytearrays; "
    "store lightweight path data instead"
)
'''
probe_result = subprocess.run(
    [sys.executable, "-c", probe],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    timeout=30,
    preexec_fn=child_limit,
)
assert probe_result.returncode == 0, (
    "Traversal implementation check failed:\n"
    f"stdout:\n{probe_result.stdout}\nstderr:\n{probe_result.stderr}"
)
PY_EOF

if python3 /tmp/verify_service_resolver.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
