#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import socket
import subprocess

import redis
import requests

SUCCESS = "/tmp/success.log"
SCHEMA = "/tmp/legacy_schema.json"
r = redis.Redis(host="127.0.0.1", port=6379, decode_responses=True)


def migrate():
    response = requests.post("http://127.0.0.1:8080/migrate", timeout=5)
    assert response.status_code == 200, (
        f"Expected 200 OK from POST /migrate, got {response.status_code}. "
        f"Body: {response.text}"
    )


def get_node(node_id):
    response = requests.get(f"http://127.0.0.1:8080/node/{node_id}", timeout=5)
    assert response.status_code == 200, (
        f"Expected 200 OK from GET /node/{node_id}, got {response.status_code}. "
        f"Body: {response.text}"
    )
    try:
        return response.json()
    except ValueError as exc:
        raise AssertionError(f"GET /node/{node_id} returned invalid JSON: {response.text}") from exc


def tcp_asm(node_id):
    with socket.create_connection(("127.0.0.1", 9000), timeout=5) as sock:
        sock.settimeout(5)
        sock.sendall((node_id + "\n").encode())
        with sock.makefile("rb") as stream:
            line = stream.readline()
    assert line, f"TCP server returned no response for {node_id}"
    return line.decode().strip()


def load_schema(path):
    assert os.path.isfile(path), f"Expected dumped schema at {path} is missing."
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    assert isinstance(data, list), f"Expected JSON array in {path}."
    return data


def schema_by_id(data):
    result = {}
    for node in data:
        assert isinstance(node, dict), f"Schema entry is not an object: {node!r}"
        node_id = node.get("id")
        assert isinstance(node_id, str) and node_id, f"Schema entry has invalid id: {node!r}"
        assert node_id not in result, f"Duplicate schema id: {node_id}"
        result[node_id] = node
    return result


def expected_asm(bytecode):
    opcodes = {"00": "NOP", "01": "PUSH", "02": "POP", "03": "ADD"}
    assert len(bytecode) % 2 == 0
    return " ".join(opcodes[bytecode[i:i + 2]] for i in range(0, len(bytecode), 2))


# Preserve the original final-state assertions before modifying any test data.
assert os.path.isfile(SUCCESS), f"Expected success log at {SUCCESS} is missing."
with open(SUCCESS, encoding="utf-8") as handle:
    success_content = handle.read().strip()
assert "READY" in success_content, f"Expected 'READY' in {SUCCESS}, got {success_content!r}."

initial_schema = load_schema(SCHEMA)
assert len(initial_schema) == 4, f"Expected 4 nodes in {SCHEMA}, got {len(initial_schema)}."
initial_by_id = schema_by_id(initial_schema)
legacy_by_id = {key: json.loads(value) for key, value in r.hgetall("legacy:nodes").items()}
assert initial_by_id == legacy_by_id, "The legacy schema dump does not match legacy:nodes."

migrate()
ordered_raw = r.get("v2:ordered_nodes")
assert ordered_raw, "Key v2:ordered_nodes is empty or does not exist."
ordered = json.loads(ordered_raw)
original_order = ["node_C", "node_B", "node_A", "node_D"]
assert ordered == original_order, f"Expected topological sort {original_order}, got {ordered}."

original_asm = {
    "node_A": "PUSH ADD",
    "node_B": "PUSH PUSH ADD",
    "node_C": "NOP",
    "node_D": "POP POP",
}
initial_hash = r.hgetall("v2:nodes")
assert set(initial_hash) == set(original_asm), f"v2:nodes has unexpected fields: {set(initial_hash)}"
for node_id, asm in original_asm.items():
    http_node = get_node(node_id)
    assert http_node.get("id") == node_id, f"Expected node id {node_id}, got {http_node.get('id')}."
    assert http_node.get("asm") == asm, f"Expected asm {asm!r} for {node_id}, got {http_node.get('asm')!r}."
    assert tcp_asm(node_id) == asm, f"TCP returned incorrect assembly for {node_id}."

    stored = json.loads(initial_hash[node_id])
    source = initial_by_id[node_id]
    assert stored.get("id") == node_id
    assert stored.get("deps") == source.get("deps"), f"v2:nodes lost deps for {node_id}."
    assert stored.get("bytecode") == source.get("bytecode"), f"v2:nodes lost bytecode for {node_id}."
    assert stored.get("asm") == asm, f"v2:nodes has incorrect asm for {node_id}."

# Verify that setup.py is installable and the installed dumper actually reads Redis.
install = subprocess.run(
    ["python3", "-m", "pip", "install", "-e", "/app/py_graph_dumper"],
    text=True,
    capture_output=True,
    timeout=60,
)
assert install.returncode == 0, f"pip install -e failed:\n{install.stdout}\n{install.stderr}"
assert shutil.which("dumper"), "The dumper console command was not installed."

# Add unpredictable nodes so fixed answers cannot satisfy graph, bytecode, HTTP, TCP,
# and Redis migration checks. Keep the original graph so this remains the same task.
token = secrets.token_hex(8)
ids = [f"dynamic_{token}_{suffix}" for suffix in ("root", "middle", "leaf")]
root, middle, leaf = ids
bytecodes = {
    root: "".join(secrets.choice(("00", "01", "02", "03")) for _ in range(7)),
    middle: "".join(secrets.choice(("00", "01", "02", "03")) for _ in range(8)),
    leaf: "".join(secrets.choice(("00", "01", "02", "03")) for _ in range(9)),
}
dynamic_nodes = {
    root: {"id": root, "deps": [], "bytecode": bytecodes[root]},
    middle: {"id": middle, "deps": [root], "bytecode": bytecodes[middle]},
    leaf: {"id": leaf, "deps": [middle, "node_D"], "bytecode": bytecodes[leaf]},
}
for node_id, node in dynamic_nodes.items():
    r.hset("legacy:nodes", node_id, json.dumps(node))

run_dump = subprocess.run(
    ["dumper", "--output", SCHEMA],
    text=True,
    capture_output=True,
    timeout=15,
)
assert run_dump.returncode == 0, f"Installed dumper failed:\n{run_dump.stdout}\n{run_dump.stderr}"

dumped = load_schema(SCHEMA)
dumped_by_id = schema_by_id(dumped)
current_legacy = {key: json.loads(value) for key, value in r.hgetall("legacy:nodes").items()}
assert dumped_by_id == current_legacy, "Installed dumper output does not match the current legacy:nodes hash."

migrate()
ordered_raw = r.get("v2:ordered_nodes")
assert ordered_raw, "v2:ordered_nodes is missing after dynamic migration."
ordered = json.loads(ordered_raw)
assert isinstance(ordered, list), "v2:ordered_nodes must contain a JSON array."
assert len(ordered) == len(current_legacy), "v2:ordered_nodes has the wrong number of nodes."
assert len(set(ordered)) == len(ordered), "v2:ordered_nodes contains duplicate node IDs."
assert set(ordered) == set(current_legacy), "v2:ordered_nodes does not contain exactly the migrated nodes."
positions = {node_id: index for index, node_id in enumerate(ordered)}
for node_id, node in current_legacy.items():
    for dep in node.get("deps", []):
        assert dep in positions, f"Dependency {dep} of {node_id} is missing from ordered output."
        assert positions[dep] < positions[node_id], f"Dependency {dep} appears after {node_id}."

migrated_hash = r.hgetall("v2:nodes")
assert set(migrated_hash) == set(current_legacy), "v2:nodes does not contain exactly the migrated node IDs."
for node_id in ids:
    asm = expected_asm(bytecodes[node_id])
    stored = json.loads(migrated_hash[node_id])
    assert stored.get("id") == node_id
    assert stored.get("deps") == dynamic_nodes[node_id]["deps"]
    assert stored.get("bytecode") == bytecodes[node_id]
    assert stored.get("asm") == asm, f"Incorrect Redis asm for dynamic node {node_id}."

    http_node = get_node(node_id)
    assert http_node.get("id") == node_id
    assert http_node.get("deps") == dynamic_nodes[node_id]["deps"]
    assert http_node.get("bytecode") == bytecodes[node_id]
    assert http_node.get("asm") == asm, f"Incorrect HTTP asm for dynamic node {node_id}."
    assert tcp_asm(node_id) == asm, f"Incorrect TCP asm for dynamic node {node_id}."
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
