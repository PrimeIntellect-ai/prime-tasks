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
import socket
import threading
import time

import numpy as np
import pytest
import requests


def get_json(url):
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx on port 8080 or request timed out: {e}")

    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")


def test_api_signal_endpoint():
    """Test the /api/signal endpoint via Nginx."""
    data = get_json("http://127.0.0.1:8080/api/signal")
    assert "dominant_frequency" in data, f"Key 'dominant_frequency' missing in response: {data}"

    # The simulator generates a 42 Hz signal
    assert data["dominant_frequency"] == 42, (
        f"Expected dominant frequency to be 42, got {data['dominant_frequency']}"
    )


def test_api_graph_endpoint_42():
    """Test the /api/graph/<freq> endpoint with freq=42 via Nginx."""
    data = get_json("http://127.0.0.1:8080/api/graph/42")
    assert "max_component_size" in data, f"Key 'max_component_size' missing in response: {data}"

    # For freq=42, the resonating nodes are 1, 2, 3, 6. They form a connected component of size 4.
    assert data["max_component_size"] == 4, (
        f"Expected max_component_size to be 4, got {data['max_component_size']}"
    )


def test_api_graph_endpoint_100():
    """Test the /api/graph/<freq> endpoint with freq=100 via Nginx."""
    data = get_json("http://127.0.0.1:8080/api/graph/100")
    assert "max_component_size" in data, f"Key 'max_component_size' missing in response: {data}"

    # For freq=100, only node 5 resonates. Max component size is 1.
    assert data["max_component_size"] == 1, (
        f"Expected max_component_size to be 1, got {data['max_component_size']}"
    )


def test_processor_file_exists():
    """Ensure the processor file was created."""
    assert os.path.isfile("/app/processor.py"), "Expected /app/processor.py to exist, but it does not."


def stop_original_simulator():
    me = os.getpid()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == me:
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                cmdline = f.read()
            if b"/app/simulator.py" in cmdline:
                os.kill(int(entry), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass


class SignalServer:
    def __init__(self, values):
        self.payload = json.dumps(values).encode("utf-8")
        self.error = None
        self.consumed = False
        self.sock = None

        deadline = time.time() + 3
        while time.time() < deadline:
            candidate = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            candidate.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            try:
                candidate.bind(("127.0.0.1", 9000))
                candidate.listen(2)
                candidate.settimeout(6)
                self.sock = candidate
                break
            except OSError:
                candidate.close()
                time.sleep(0.05)
        if self.sock is None:
            pytest.fail("Could not take control of simulator port 9000")

        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def run(self):
        try:
            conn, _ = self.sock.accept()
            with conn:
                conn.sendall(self.payload)
            self.consumed = True
        except Exception as exc:
            self.error = exc
        finally:
            self.sock.close()

    def verify_consumed(self):
        self.thread.join(timeout=7)
        assert self.error is None, f"Controlled simulator failed: {self.error}"
        assert self.consumed, "The processor did not connect to the simulator on port 9000"


def test_signal_is_computed_from_fresh_simulator_data():
    """Replace the simulator stream and verify that each response follows its FFT."""
    stop_original_simulator()
    time.sleep(0.2)

    rng = np.random.default_rng(secrets.randbits(64))
    frequencies = rng.choice(
        np.array([7, 19, 31, 57, 73, 91, 123, 177, 221, 301, 403]),
        size=3,
        replace=False,
    )

    for freq in frequencies:
        phase1 = rng.uniform(0, 2 * np.pi)
        phase2 = rng.uniform(0, 2 * np.pi)
        secondary = int(rng.choice([11, 27, 64, 109, 155]))
        if secondary == int(freq):
            secondary += 3
        t = np.arange(1024) / 1024.0
        values = (
            1.7 * np.sin(2 * np.pi * int(freq) * t + phase1)
            + 0.23 * np.sin(2 * np.pi * secondary * t + phase2)
            + rng.normal(0, 0.015, 1024)
        ).tolist()
        expected = int(np.argmax(np.abs(np.fft.rfft(np.asarray(values)))[1:]) + 1)

        server = SignalServer(values)
        data = get_json("http://127.0.0.1:8080/api/signal")
        server.verify_consumed()
        assert "dominant_frequency" in data, data
        assert data["dominant_frequency"] == expected, (
            f"Expected FFT-derived frequency {expected}, got {data['dominant_frequency']}"
        )


def graph_answer(graph, requested):
    resonating = {
        node["id"] for node in graph["nodes"]
        if abs(node["base_freq"] - requested) < 3.0
    }
    adjacency = {node_id: set() for node_id in resonating}
    for left, right in graph["edges"]:
        if left in resonating and right in resonating:
            adjacency[left].add(right)
            adjacency[right].add(left)

    largest = 0
    seen = set()
    for start in resonating:
        if start in seen:
            continue
        stack = [start]
        seen.add(start)
        size = 0
        while stack:
            current = stack.pop()
            size += 1
            for neighbor in adjacency[current]:
                if neighbor not in seen:
                    seen.add(neighbor)
                    stack.append(neighbor)
        largest = max(largest, size)
    return largest


def test_graph_is_computed_from_current_molecule_file():
    """Exercise randomized graphs, frequencies, boundaries, and induced components."""
    path = "/app/molecule.json"
    with open(path, "rb") as f:
        original = f.read()

    rng = np.random.default_rng(secrets.randbits(64))
    try:
        for _ in range(7):
            requested = int(rng.integers(20, 480))
            count = int(rng.integers(7, 15))
            ids = rng.choice(np.arange(1000, 9000), size=count, replace=False).tolist()

            nodes = []
            offsets = [-3.0, 3.0, -2.75, 2.75, -1.0, 0.0, 7.0, -11.0]
            for index, node_id in enumerate(ids):
                # Include both strict-boundary and resonating cases, then randomize the rest.
                if index < len(offsets):
                    offset = offsets[index]
                else:
                    offset = float(rng.uniform(-12, 12))
                nodes.append({"id": int(node_id), "base_freq": requested + offset})

            edges = []
            for i in range(count):
                for j in range(i + 1, count):
                    if rng.random() < 0.28:
                        edges.append([int(ids[i]), int(ids[j])])
            rng.shuffle(nodes)
            rng.shuffle(edges)
            graph = {"nodes": nodes, "edges": edges}
            expected = graph_answer(graph, requested)

            temp = path + ".verifier_tmp"
            with open(temp, "w") as f:
                json.dump(graph, f)
            os.replace(temp, path)

            data = get_json(f"http://127.0.0.1:8080/api/graph/{requested}")
            assert "max_component_size" in data, data
            assert data["max_component_size"] == expected, (
                f"For generated graph and freq={requested}, expected {expected}, "
                f"got {data['max_component_size']}"
            )
    finally:
        with open(path, "wb") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
