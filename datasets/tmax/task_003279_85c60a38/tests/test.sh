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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import re
import secrets
import string
import subprocess
import time
from collections import defaultdict

import pytest
import requests

BASE_URL = "http://127.0.0.1:8000"
IMAGE = "/app/dataset_lineage.png"
EXPECTED_EDGES = {
    ("ALPHA", "BETA"),
    ("ALPHA", "GAMMA"),
    ("BETA", "DELTA"),
    ("BETA", "OMEGA"),
    ("GAMMA", "DELTA"),
    ("THETA", "RHO"),
    ("RHO", "OMEGA"),
    ("DELTA", "OMEGA"),
}


def wait_for_server(url, timeout=5):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            requests.get(url, timeout=1)
            return True
        except requests.exceptions.RequestException:
            time.sleep(0.5)
    return False


@pytest.fixture(scope="module", autouse=True)
def check_server_up():
    assert wait_for_server(f"{BASE_URL}/"), \
        f"Could not connect to API server at {BASE_URL}. Is it running?"


def query(endpoint, dataset):
    url = f"{BASE_URL}/{endpoint}"
    try:
        response = requests.get(url, params={"dataset": dataset}, timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Request to {url} failed: {exc}")
    assert response.status_code == 200, \
        f"Expected status 200 from {response.url}, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from {response.url} is not valid JSON. Response text: {response.text}")
    assert isinstance(data, dict), f"Expected a JSON object from {response.url}, got {data!r}"
    assert endpoint in data, f"Key {endpoint!r} missing in response from {response.url}. Got: {data}"
    return data[endpoint]


def ocr_edges():
    try:
        result = subprocess.run(
            ["tesseract", IMAGE, "stdout"],
            check=True,
            capture_output=True,
            text=True,
            timeout=15,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        pytest.fail(f"Could not OCR {IMAGE}: {exc}")

    edges = set()
    for line in result.stdout.splitlines():
        names = re.findall(r"[A-Z]+", line.upper())
        if not names:
            continue
        assert len(names) == 2, f"Could not parse OCR lineage line {line!r}"
        edges.add((names[0], names[1]))
    assert edges == EXPECTED_EDGES, \
        f"OCR did not recover the expected graph. Recovered edges: {sorted(edges)}"
    return edges


def closures(edges):
    forward = defaultdict(set)
    reverse = defaultdict(set)
    nodes = set()
    for source, destination in edges:
        forward[source].add(destination)
        reverse[destination].add(source)
        nodes.update((source, destination))

    def reachable(start, adjacency):
        found = set()
        pending = list(adjacency[start])
        while pending:
            node = pending.pop()
            if node in found:
                continue
            found.add(node)
            pending.extend(adjacency[node] - found)
        return sorted(found)

    upstream = {node: reachable(node, reverse) for node in nodes}
    downstream = {node: reachable(node, forward) for node in nodes}
    return nodes, upstream, downstream


def test_original_fixed_assertions():
    assert query("upstream", "OMEGA") == ["ALPHA", "BETA", "DELTA", "GAMMA", "RHO", "THETA"]
    assert query("downstream", "ALPHA") == ["BETA", "DELTA", "GAMMA", "OMEGA"]
    assert query("upstream", "ALPHA") == []
    assert query("downstream", "OMEGA") == []


def test_every_node_and_nonexistent_datasets():
    nodes, upstream, downstream = closures(ocr_edges())

    checks = []
    for node in nodes:
        checks.append(("upstream", node, upstream[node]))
        checks.append(("downstream", node, downstream[node]))

    unknowns = {"NONEXISTENT", "ZETA"}
    while len(unknowns) < 6:
        unknowns.add("".join(secrets.choice(string.ascii_uppercase) for _ in range(24)))
    unknowns -= nodes
    for node in unknowns:
        checks.append(("upstream", node, []))
        checks.append(("downstream", node, []))

    secrets.SystemRandom().shuffle(checks)
    for endpoint, node, expected in checks:
        actual = query(endpoint, node)
        assert actual == expected, \
            f"Expected {endpoint} for {node} to be {expected}, got {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
