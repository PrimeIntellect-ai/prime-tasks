#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import subprocess
import time
import uuid
from pathlib import Path

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"


def wait_for_service(url, timeout=5):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            requests.get(url, timeout=1)
            return True
        except requests.RequestException:
            time.sleep(0.25)
    return False


def get_impact(corrupted_id):
    try:
        response = requests.get(
            BASE_URL + "/api/impact",
            params={"corrupted_id": corrupted_id},
            timeout=5,
        )
    except requests.ConnectionError:
        pytest.fail("Failed to connect to the service at 127.0.0.1:8080. Is it running?")

    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    assert "impacted" in data, "JSON response missing 'impacted' key."
    return data


def listener_pids(port=8080):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10:
                continue
            try:
                local_port = int(fields[1].rsplit(":", 1)[1], 16)
            except (ValueError, IndexError):
                continue
            if local_port == port and fields[3] == "0A":
                inodes.add(fields[9])

    found = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    found.add(int(proc.name))
                    break
        except OSError:
            continue
    return sorted(found)


def process_launch_info(pid):
    raw_args = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    argv = [os.fsdecode(value) for value in raw_args if value]
    assert argv, "Could not determine the service command line"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = {}
    for entry in Path(f"/proc/{pid}/environ").read_bytes().split(b"\0"):
        if b"=" in entry:
            key, value = entry.split(b"=", 1)
            env[os.fsdecode(key)] = os.fsdecode(value)
    # A Flask reloader child cannot be relaunched using stale inherited FDs.
    env.pop("WERKZEUG_RUN_MAIN", None)
    env.pop("WERKZEUG_SERVER_FD", None)
    return argv, cwd, env


def restart_service_after_graph_change():
    pids = listener_pids()
    assert pids, "No process is listening on port 8080"
    argv, cwd, env = process_launch_info(pids[0])

    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    deadline = time.time() + 3
    while time.time() < deadline and listener_pids():
        time.sleep(0.1)

    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    subprocess.Popen(
        argv,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    assert wait_for_service(BASE_URL + "/api/impact?corrupted_id=readiness-check", 10), (
        "Service did not restart after the RDF graph was changed"
    )


def test_impact_endpoint_delta_92():
    wait_for_service(BASE_URL + "/")
    data = get_impact("delta-92")
    expected_impacted = {"epsilon-93", "zeta-94"}
    actual_impacted = set(data["impacted"])
    assert actual_impacted == expected_impacted, (
        f"Expected impacted snapshots {expected_impacted}, but got {actual_impacted}"
    )


def test_impact_endpoint_gamma_30():
    data = get_impact("gamma-30")
    expected_impacted = {"delta-92", "epsilon-93", "zeta-94"}
    actual_impacted = set(data["impacted"])
    assert actual_impacted == expected_impacted, (
        f"Expected impacted snapshots {expected_impacted}, but got {actual_impacted}"
    )


def test_dynamic_topology_and_arbitrary_chain_lengths():
    token = uuid.uuid4().hex
    chain = [f"verify-{token}-{i}" for i in range(13)]
    branch_a = f"verify-{token}-branch-a"
    branch_b = f"verify-{token}-branch-b"
    isolated = f"verify-{token}-isolated"

    edges = [(chain[i], chain[i - 1]) for i in range(1, len(chain))]
    edges.extend([(branch_a, chain[3]), (branch_b, branch_a)])

    lines = ["@prefix ex: <http://example.org/backup/> .", ""]
    lines.extend(f"ex:{child} ex:dependsOn ex:{parent} ." for child, parent in edges)
    # Mention an isolated resource without creating a dependency edge.
    lines.append(f"ex:{isolated} a <http://example.org/backup/Snapshot> .")
    Path("/app/backup_topology.ttl").write_text("\n".join(lines) + "\n")

    restart_service_after_graph_change()

    def descendants(target):
        result = set()
        frontier = [target]
        while frontier:
            parent = frontier.pop()
            for child, edge_parent in edges:
                if edge_parent == parent and child not in result:
                    result.add(child)
                    frontier.append(child)
        return result

    # IDs and expected closures are generated only after the agent has finished.
    for target in (chain[0], chain[3], chain[8], branch_a, chain[-1], isolated):
        data = get_impact(target)
        assert isinstance(data, dict) and set(data) == {"impacted"}, (
            f"Response must have exactly the required JSON shape, got {data!r}"
        )
        assert isinstance(data["impacted"], list), "'impacted' must be a JSON array"
        assert all(isinstance(item, str) and "://" not in item for item in data["impacted"]), (
            "Impacted entries must be URI local-name strings"
        )
        actual = set(data["impacted"])
        expected = descendants(target)
        assert actual == expected, (
            f"For dynamically generated target {target}, expected {expected}, got {actual}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
