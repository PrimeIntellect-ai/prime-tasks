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
import secrets
import signal
import subprocess
import time
from collections import defaultdict

import pytest
import requests

BASE_URL = "http://127.0.0.1:8888"
DATA_PATH = "/app/transactions.jsonl"
PORT_HEX = format(8888, "04X")


def load_transactions():
    rows = []
    with open(DATA_PATH, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                rows.append(json.loads(line))
    return rows


def expected_volume(rows, minimum):
    totals = defaultdict(float)
    for row in rows:
        if float(row["amount"]) >= minimum:
            totals[str(row["src"])] += float(row["amount"])
    return max(totals.values()) if totals else 0.0


def expected_top_node(rows, alpha=0.85):
    nodes = set()
    outgoing = defaultdict(set)
    for row in rows:
        src, dst = str(row["src"]), str(row["dst"])
        nodes.update((src, dst))
        outgoing[src].add(dst)

    assert nodes, "Transaction graph is empty"
    nodes = sorted(nodes)
    n = len(nodes)
    ranks = {node: 1.0 / n for node in nodes}

    for _ in range(1000):
        dangling = sum(ranks[node] for node in nodes if not outgoing[node])
        new_ranks = {node: (1.0 - alpha) / n + alpha * dangling / n for node in nodes}
        for src in nodes:
            if outgoing[src]:
                share = alpha * ranks[src] / len(outgoing[src])
                for dst in outgoing[src]:
                    new_ranks[dst] += share
        error = sum(abs(new_ranks[node] - ranks[node]) for node in nodes)
        ranks = new_ranks
        if error < 1e-12:
            break

    return max(nodes, key=lambda node: ranks[node])


def request_json(method, path, payload=None):
    url = BASE_URL + path
    try:
        response = requests.request(method, url, json=payload, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to {url}: {exc}")
    assert response.status_code == 200, (
        f"Expected status code 200 from {path}, got {response.status_code}: {response.text}"
    )
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response from {path} is not valid JSON: {response.text}")


def listener_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(":")[-1].upper() == PORT_HEX and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(entry)
        except OSError:
            continue
    return None


def process_launch_info(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        argv = [part.decode("utf-8", "surrogateescape") for part in f.read().split(b"\0") if part]
    assert argv, "Could not determine the server command line"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = {}
    with open(f"/proc/{pid}/environ", "rb") as f:
        for item in f.read().split(b"\0"):
            if b"=" in item:
                key, value = item.split(b"=", 1)
                env[key.decode("utf-8", "surrogateescape")] = value.decode("utf-8", "surrogateescape")
    return argv, cwd, env


def wait_until_ready(timeout=10):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(BASE_URL + "/graph/centrality", timeout=0.5)
            if response.status_code == 200:
                return
        except requests.exceptions.RequestException as exc:
            last_error = exc
        time.sleep(0.15)
    pytest.fail(f"Server did not become ready after restart: {last_error}")


def restart_server_from_artifact():
    pid = listener_pid()
    assert pid is not None, "No process is listening on the required port 8888"
    argv, cwd, env = process_launch_info(pid)

    os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 3
    while time.time() < deadline and os.path.exists(f"/proc/{pid}"):
        time.sleep(0.05)
    if os.path.exists(f"/proc/{pid}"):
        os.kill(pid, signal.SIGKILL)

    # A process supervisor may have restarted the service itself.
    time.sleep(0.5)
    if listener_pid() is None:
        try:
            subprocess.Popen(
                argv,
                cwd=cwd,
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except OSError as exc:
            pytest.fail(f"Could not execute the submitted server artifact: {exc}")
    wait_until_ready()


def test_graph_centrality():
    rows = load_transactions()
    expected = expected_top_node(rows)
    data = request_json("GET", "/graph/centrality")
    assert "top_node" in data, "Response JSON missing 'top_node' key"
    assert data["top_node"] == expected, f"Expected top_node {expected!r}, got {data['top_node']!r}"
    assert data["top_node"] == "U3", f"Expected top_node 'U3', got {data['top_node']!r}"


def test_nosql_aggregate():
    rows = load_transactions()
    expected = expected_volume(rows, 100)
    data = request_json("POST", "/nosql/aggregate", {"min_amount": 100})
    assert "top_sender_volume" in data, "Response JSON missing 'top_sender_volume' key"
    assert data["top_sender_volume"] == pytest.approx(expected)
    assert data["top_sender_volume"] == pytest.approx(300)


def test_service_uses_dataset_and_dynamic_parameters():
    with open(DATA_PATH, "rb") as f:
        original_data = f.read()

    suffix = secrets.token_hex(5)
    hub = "H_" + suffix
    leaves = [f"L{i}_{suffix}" for i in range(5)]
    offset = secrets.randbelow(1000) + 1
    specifications = [
        (leaves[0], hub, 100 + offset),
        (leaves[0], hub, 400 + offset),
        (leaves[1], hub, 250 + offset),
        (leaves[1], hub, 300 + offset),
        (leaves[2], hub, 450 + offset),
        (leaves[3], hub, 150 + offset),
        (leaves[3], hub, 350 + offset),
        (leaves[4], hub, 200 + offset),
        (hub, leaves[0], 50 + offset),
    ]
    rows = [{"src": src, "dst": dst, "amount": amount} for src, dst, amount in specifications]

    try:
        with open(DATA_PATH, "w", encoding="utf-8") as f:
            for row in rows:
                f.write(json.dumps(row) + "\n")

        restart_server_from_artifact()

        expected_node = expected_top_node(rows)
        assert expected_node == hub, "Internal synthetic graph did not have the intended unique top node"
        graph_data = request_json("GET", "/graph/centrality")
        assert "top_node" in graph_data, "Response JSON missing 'top_node' key"
        assert graph_data["top_node"] == expected_node, (
            f"Expected top_node {expected_node!r} for the replacement dataset, got {graph_data['top_node']!r}"
        )

        amounts = sorted({float(row["amount"]) for row in rows})
        thresholds = [amounts[0] - 0.5]
        thresholds.extend(amounts)
        thresholds.extend((left + right) / 2.0 for left, right in zip(amounts, amounts[1:]))

        observed = set()
        for threshold in thresholds:
            expected = expected_volume(rows, threshold)
            data = request_json("POST", "/nosql/aggregate", {"min_amount": threshold})
            assert "top_sender_volume" in data, "Response JSON missing 'top_sender_volume' key"
            assert data["top_sender_volume"] == pytest.approx(expected), (
                f"Wrong aggregation for min_amount={threshold}: expected {expected}, "
                f"got {data['top_sender_volume']}"
            )
            observed.add(expected)
        assert len(observed) >= 2, "Internal dynamic cases did not produce distinct expected results"
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
