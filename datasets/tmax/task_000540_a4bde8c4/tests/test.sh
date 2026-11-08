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
import json
import os
import random
import secrets
import stat
import uuid

import pytest
import requests

URL = "http://127.0.0.1:9000/build-order"
TOKEN = "DELTA-NINER-WHISKEY-TWO"
GRAPH_PATH = "/home/user/mobile_graph.json"

SESSION = requests.Session()
SESSION.trust_env = False


def compute_expected_order(graph):
    graph = {node: list(deps) for node, deps in graph.items()}
    in_degree = {u: 0 for u in graph}
    for u in graph:
        for v in graph[u]:
            if v not in in_degree:
                in_degree[v] = 0
            in_degree[u] += 1

    for u in list(in_degree.keys()):
        if u not in graph:
            graph[u] = []

    queue = sorted(u for u in in_degree if in_degree[u] == 0)
    order = []
    while queue:
        u = queue.pop(0)
        order.append(u)
        for node, deps in graph.items():
            if u in deps:
                in_degree[node] -= 1
                if in_degree[node] == 0:
                    queue.append(node)
                    queue.sort()
    return order


def request(method, url, **kwargs):
    kwargs.setdefault("timeout", 2)
    try:
        return SESSION.request(method, url, **kwargs)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Server is not running or unreachable at {url}: {exc}")


def install_graph(graph):
    temporary = f"{GRAPH_PATH}.verifier-{uuid.uuid4().hex}"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(graph, handle)
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, 0o644)
    os.replace(temporary, GRAPH_PATH)


def listening_sockets_on_9000():
    found = []
    for table, family in (("/proc/net/tcp", "ipv4"), ("/proc/net/tcp6", "ipv6")):
        if not os.path.exists(table):
            continue
        with open(table, "r", encoding="ascii") as handle:
            next(handle, None)
            for line in handle:
                fields = line.split()
                if len(fields) < 10 or fields[3] != "0A":
                    continue
                address, port = fields[1].rsplit(":", 1)
                if int(port, 16) == 9000:
                    found.append((family, address, fields[9]))
    return found


def test_01_python_server_listens_exactly_on_loopback_9000():
    listeners = listening_sockets_on_9000()
    assert listeners, "No listening socket was found on port 9000"
    assert all(family == "ipv4" and address == "0100007F" for family, address, _ in listeners), \
        f"Port 9000 must listen exactly on 127.0.0.1, found {listeners}"

    socket_inodes = {inode for _, _, inode in listeners}
    python_owner = False
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            descriptors = os.listdir(fd_dir)
        except OSError:
            continue
        owns_socket = False
        for descriptor in descriptors:
            try:
                target = os.readlink(f"{fd_dir}/{descriptor}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                owns_socket = True
                break
        if not owns_socket:
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as handle:
                command = handle.read().replace(b"\x00", b" ").lower()
            executable = os.path.basename(os.readlink(f"/proc/{pid}/exe")).lower().encode()
        except OSError:
            continue
        if b"python" in command or b"python" in executable:
            python_owner = True
            break
    assert python_owner, "The listener on 127.0.0.1:9000 is not owned by a Python process"


def test_02_server_running_and_unauthorized_no_token():
    response = request("GET", URL)
    assert response.status_code == 401, \
        f"Expected 401 Unauthorized when no token is provided, got {response.status_code}"


def test_03_unauthorized_wrong_token():
    response = request("GET", URL, headers={"Authorization": "Bearer WRONG-TOKEN"})
    assert response.status_code == 401, \
        f"Expected 401 Unauthorized when wrong token is provided, got {response.status_code}"


def test_04_authorized_correct_response_for_existing_graph():
    assert os.path.isfile(GRAPH_PATH), f"Graph file missing at {GRAPH_PATH}"
    with open(GRAPH_PATH, "r", encoding="utf-8") as handle:
        graph = json.load(handle)
    expected_order = compute_expected_order(graph)

    response = request("GET", URL, headers={"Authorization": f"Bearer {TOKEN}"})
    assert response.status_code == 200, \
        f"Expected 200 OK with correct token, got {response.status_code}"
    try:
        actual_order = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")
    assert actual_order == expected_order, \
        f"Expected build order {expected_order}, but got {actual_order}"


def test_05_authentication_applies_to_other_paths_and_only_endpoint_exists():
    unknown = f"http://127.0.0.1:9000/{secrets.token_hex(12)}"
    for headers in (None, {"Authorization": "Bearer WRONG-TOKEN"},
                    {"Authorization": TOKEN},
                    {"Authorization": f"Bearer {TOKEN} trailing"}):
        response = request("GET", unknown, headers=headers)
        assert response.status_code == 401, \
            f"Every unauthenticated request must return 401; got {response.status_code} for {unknown}"

    good_headers = {"Authorization": f"Bearer {TOKEN}"}
    assert request("GET", unknown, headers=good_headers).status_code == 404, \
        "An authenticated unknown path must not be exposed as an endpoint"
    assert request("GET", URL + "/", headers=good_headers).status_code == 404, \
        "Only the exact /build-order path may be exposed"


def make_random_dag():
    count = random.SystemRandom().randint(7, 13)
    nonce = secrets.token_hex(5).upper()
    nodes = [f"MOD_{nonce}_{secrets.token_hex(4).upper()}" for _ in range(count)]
    rank = list(nodes)
    random.SystemRandom().shuffle(rank)
    graph = {}
    for index, node in enumerate(rank):
        possible_dependencies = rank[:index]
        dependencies = [dep for dep in possible_dependencies if secrets.randbelow(100) < 38]
        graph[node] = dependencies
    return graph


def test_06_reads_current_graph_and_topologically_sorts_unseen_inputs():
    with open(GRAPH_PATH, "rb") as handle:
        original = handle.read()
    original_mode = stat.S_IMODE(os.stat(GRAPH_PATH).st_mode)
    restore_path = f"{GRAPH_PATH}.restore-{uuid.uuid4().hex}"

    prefix = secrets.token_hex(6).upper()
    graphs = [
        {
            f"{prefix}_TARGET": [f"{prefix}_BETA", f"{prefix}_ALPHA"],
            f"{prefix}_BETA": [f"{prefix}_BASE_B"],
            f"{prefix}_ALPHA": [f"{prefix}_BASE_A"],
            f"{prefix}_BASE_B": [],
            f"{prefix}_BASE_A": [],
            f"{prefix}_INDEPENDENT": [],
        },
        make_random_dag(),
        make_random_dag(),
        make_random_dag(),
    ]

    try:
        for graph in graphs:
            install_graph(graph)
            expected = compute_expected_order(graph)
            response = request(
                "GET", URL,
                headers={"Authorization": f"Bearer {TOKEN}"},
            )
            assert response.status_code == 200, \
                f"Expected 200 for a valid dynamically supplied graph, got {response.status_code}"
            try:
                actual = response.json()
            except ValueError:
                pytest.fail("Dynamic graph response is not valid JSON")
            assert actual == expected, \
                f"Server did not compute the deterministic order for the current graph: expected {expected}, got {actual}"
    finally:
        with open(restore_path, "wb") as handle:
            handle.write(original)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(restore_path, original_mode)
        os.replace(restore_path, GRAPH_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
