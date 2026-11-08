#!/bin/bash
set -u
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
PACKAGE = "/app/vendored/simple-graph-db"
BINARY = f"{PACKAGE}/build/graph_server"
GRAPH = "/app/data/edges.csv"
TEST_PORT = 18080
TEST_URL = f"http://127.0.0.1:{TEST_PORT}"


def expected_results(limit, offset):
    # Independently reproduce the vendored engine's centrality dataset.
    ranked = [{"id": node_id, "score": float(20 - node_id)}
              for node_id in range(1, 21)]
    start = min(offset, len(ranked))
    end = min(start + limit, len(ranked))
    return ranked[start:end]


def get_json(base_url, limit, offset):
    response = requests.get(
        f"{base_url}/api/top_centrality",
        params={"limit": limit, "offset": offset},
        timeout=2,
    )
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    data = response.json()
    assert isinstance(data, list), "Response should be a JSON array"
    return data


def wait_for_server(url, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            response = requests.get(url, timeout=0.5)
            if response.status_code == 200:
                return True
        except requests.RequestException:
            pass
        time.sleep(0.1)
    return False


def deployed_process_has_required_arguments():
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            raw = open(f"/proc/{entry}/cmdline", "rb").read()
            argv = [part.decode(errors="replace") for part in raw.split(b"\0") if part]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if not argv or "graph_server" not in argv[0]:
            continue
        if "--port" not in argv or "--graph" not in argv:
            continue
        try:
            port = argv[argv.index("--port") + 1]
            graph = argv[argv.index("--graph") + 1]
        except (ValueError, IndexError):
            continue
        if port == "8080" and os.path.abspath(graph) == GRAPH:
            return True
    return False


@pytest.fixture(scope="module", autouse=True)
def ensure_server_running():
    url = f"{BASE_URL}/api/top_centrality?limit=1&offset=0"
    assert wait_for_server(url), "Server is not reachable at 127.0.0.1:8080. Did you start it?"
    assert deployed_process_has_required_arguments(), (
        "The deployed graph_server was not started with --port 8080 and "
        "--graph /app/data/edges.csv"
    )


@pytest.fixture(scope="module")
def rebuilt_server():
    with open(BINARY, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "build/graph_server must be a compiled ELF executable"

    process = subprocess.Popen(
        [BINARY, "--port", str(TEST_PORT), "--graph", GRAPH],
        cwd=PACKAGE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        assert wait_for_server(f"{TEST_URL}/api/top_centrality?limit=1&offset=0"), (
            "The rebuilt graph_server artifact did not start successfully"
        )
        yield TEST_URL
    finally:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=2)


def test_pagination_offset_and_limit():
    resp_all = requests.get(f"{BASE_URL}/api/top_centrality?limit=10&offset=0", timeout=2)
    assert resp_all.status_code == 200, f"Expected 200 OK, got {resp_all.status_code}"

    data_all = resp_all.json()
    assert isinstance(data_all, list), "Response should be a JSON array"
    assert len(data_all) == 10, "Expected 10 items in the response for limit=10"
    assert data_all == expected_results(10, 0), "Top-centrality results are incorrect"

    resp_paginated = requests.get(f"{BASE_URL}/api/top_centrality?limit=5&offset=5", timeout=2)
    assert resp_paginated.status_code == 200, f"Expected 200 OK, got {resp_paginated.status_code}"

    data_paginated = resp_paginated.json()
    assert isinstance(data_paginated, list), "Response should be a JSON array"
    assert len(data_paginated) == 5, f"Expected 5 items, got {len(data_paginated)}"
    assert data_paginated == data_all[5:10], (
        "Pagination offset logic is incorrect. Items do not match the expected slice."
    )
    assert data_paginated == expected_results(5, 5), "Paginated centrality results are incorrect"


def test_pagination_out_of_bounds():
    resp = requests.get(f"{BASE_URL}/api/top_centrality?limit=100&offset=99999", timeout=2)
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code} (server might have crashed or returned error)"

    data = resp.json()
    assert isinstance(data, list), "Response should be a JSON array"
    assert len(data) == 0, f"Expected empty array for out of bounds offset, got {len(data)} items"


@pytest.mark.parametrize("limit,offset", [(1, 0), (3, 2), (4, 9), (7, 13), (10, 17), (2, 20), (6, 200)])
def test_rebuilt_artifact_answers_independently_derived_queries(rebuilt_server, limit, offset):
    assert get_json(rebuilt_server, limit, offset) == expected_results(limit, offset)
TEST_EOF

status=0

# The requested repair is to select a C++ standard supporting string_view and optional.
if ! grep -Eq -- '-std=(c\+\+|gnu\+\+)(17|20|23|2a|2b)' /app/vendored/simple-graph-db/Makefile; then
    echo "Makefile does not select a C++17-or-newer standard" >&2
    status=1
fi

# Compile from source during verification so a standalone fake HTTP process is insufficient.
if ! make -C /app/vendored/simple-graph-db clean all; then
    status=1
fi

if [ "$status" -eq 0 ]; then
    if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
        status=1
    fi
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
