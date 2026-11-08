#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import socket
import string
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

import pytest

ORACLE_PATH = "/app/sec_linker_oracle"
CLI_PATH = "/home/user/resolve_cli.py"
API_PATH = "/home/user/linker_api.py"


def wait_for_port(port, host="127.0.0.1", timeout=10.0):
    start_time = time.time()
    while time.time() - start_time < timeout:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            if sock.connect_ex((host, port)) == 0:
                return True
        time.sleep(0.2)
    return False


def generate_graph(num_nodes, make_cyclic):
    nodes = set()
    while len(nodes) < num_nodes:
        name = "".join(random.choices(
            string.ascii_letters + string.digits,
            k=random.randint(3, 8),
        ))
        nodes.add(name)
    nodes = list(nodes)
    graph = {node: [] for node in nodes}

    for i in range(num_nodes):
        for j in range(i + 1, num_nodes):
            if random.random() < 0.3:
                graph[nodes[i]].append(nodes[j])

    if make_cyclic and num_nodes >= 2:
        cycle_len = random.randint(2, num_nodes)
        cycle_nodes = random.sample(nodes, cycle_len)
        for i in range(cycle_len):
            u = cycle_nodes[i]
            v = cycle_nodes[(i + 1) % cycle_len]
            if v not in graph[u]:
                graph[u].append(v)

    return {"libraries": graph}


def reject_identical_oracle_copies(oracle_digest, oracle_size):
    for root in ("/home/user", "/tmp"):
        for dirpath, _, filenames in os.walk(root):
            for filename in filenames:
                path = os.path.join(dirpath, filename)
                try:
                    if os.path.abspath(path) == os.path.abspath(ORACLE_PATH):
                        continue
                    if not os.path.isfile(path) or os.path.getsize(path) != oracle_size:
                        continue
                    digest = hashlib.sha256()
                    with open(path, "rb") as f:
                        for chunk in iter(lambda: f.read(1024 * 1024), b""):
                            digest.update(chunk)
                    assert digest.digest() != oracle_digest, (
                        f"Submission contains a byte-identical copy of the oracle at {path}"
                    )
                except (FileNotFoundError, PermissionError, OSError):
                    continue


@pytest.fixture(scope="module")
def prepared_cases():
    assert os.path.isfile(API_PATH), f"API server file {API_PATH} not found"
    assert os.path.isfile(CLI_PATH), f"CLI client file {CLI_PATH} not found"
    assert os.path.isfile(ORACLE_PATH), "Oracle unavailable while preparing tests"

    with open(ORACLE_PATH, "rb") as f:
        oracle_data = f.read()
    reject_identical_oracle_copies(hashlib.sha256(oracle_data).digest(), len(oracle_data))

    random.seed(42)
    cases = []
    for i in range(200):
        num_nodes = random.randint(3, 50)
        make_cyclic = random.random() < 0.2
        graph_data = generate_graph(num_nodes, make_cyclic)

        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            json.dump(graph_data, f)
            temp_path = f.name
        try:
            oracle_proc = subprocess.run(
                [ORACLE_PATH, temp_path], capture_output=True, check=False
            )
            assert oracle_proc.returncode == 0
            cases.append((i, graph_data, oracle_proc.stdout))
        finally:
            os.remove(temp_path)

    # The oracle was available to the agent for reverse engineering, but must not
    # remain available to either submitted component while they are exercised.
    os.remove(ORACLE_PATH)
    assert not os.path.exists(ORACLE_PATH)
    return cases


@pytest.fixture(scope="module")
def api_server(prepared_cases):
    assert not wait_for_port(8000, timeout=0.2), "Port 8000 was already in use"

    proc = subprocess.Popen(
        [sys.executable, API_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if not wait_for_port(8000):
        proc.terminate()
        stdout, stderr = proc.communicate(timeout=2)
        pytest.fail(
            "API server did not listen on port 8000 within timeout.\n"
            f"stdout: {stdout.decode(errors='replace')}\n"
            f"stderr: {stderr.decode(errors='replace')}"
        )
    assert proc.poll() is None, "Submitted API process exited during startup"

    yield proc

    proc.terminate()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)


def post_graph(graph_data):
    request = urllib.request.Request(
        "http://127.0.0.1:8000/api/v1/resolve",
        data=json.dumps(graph_data).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        assert response.status == 200
        return json.loads(response.read().decode("utf-8"))


def test_fuzz_equivalence(api_server, prepared_cases):
    for i, graph_data, oracle_bytes in prepared_cases:
        oracle_out = oracle_bytes.decode("utf-8")
        expected_status = (
            "error" if oracle_out == "FATAL: Cyclic dependency detected.\n" else "success"
        )

        # Exercise the required HTTP endpoint directly, independently of the CLI.
        api_result = post_graph(graph_data)
        assert api_result == {"status": expected_status, "output": oracle_out}, (
            f"API mismatch on fuzz iteration {i + 1}:\n"
            f"Input graph:\n{json.dumps(graph_data, indent=2)}\n"
            f"Expected: {json.dumps({'status': expected_status, 'output': oracle_out})}\n"
            f"Actual: {json.dumps(api_result)}"
        )

        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            json.dump(graph_data, f)
            temp_path = f.name
        try:
            agent_proc = subprocess.run(
                [sys.executable, CLI_PATH, temp_path],
                capture_output=True,
                check=False,
                timeout=10,
            )
            agent_out = agent_proc.stdout.decode("utf-8", errors="replace").strip()
            stripped_oracle = oracle_out.strip()

            # Preserve the original fuzz-equivalence assertion.
            assert agent_out == stripped_oracle, (
                f"Mismatch on fuzz iteration {i + 1}:\n"
                f"Input graph:\n{json.dumps(graph_data, indent=2)}\n\n"
                f"Oracle output:\n{stripped_oracle}\n\n"
                f"Agent output:\n{agent_out}\n"
                f"Agent stderr:\n{agent_proc.stderr.decode(errors='replace')}"
            )
            # Also enforce the instruction's bit-for-bit stdout requirement.
            assert agent_proc.returncode == 0
            assert agent_proc.stdout == oracle_bytes, (
                f"CLI stdout was not bit-for-bit identical on iteration {i + 1}"
            )
        finally:
            os.remove(temp_path)

        assert api_server.poll() is None, "Submitted API process exited during testing"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
