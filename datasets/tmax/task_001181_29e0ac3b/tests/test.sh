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
import importlib.util
import json
import math
import os
import secrets
import socket
import subprocess

import cv2
import numpy as np
import pytest
import requests

SIM_PATH = "/home/user/sim/vibration_sim.py"
DEFAULT_GRAPH_PATH = "/home/user/sim/test_graph.json"
API_URL = "http://127.0.0.1:8080/simulate"


def video_dominant_frequency():
    cap = cv2.VideoCapture("/app/reference_experiment.mp4")
    assert cap.isOpened(), "Could not open reference experiment video"
    fps = float(cap.get(cv2.CAP_PROP_FPS))
    samples = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) if frame.ndim == 3 else frame
        samples.append(float(np.mean(gray)))
    cap.release()

    assert fps > 0 and len(samples) > 2, "Reference video has no usable signal"
    signal = np.asarray(samples, dtype=np.float64)
    signal -= signal.mean()
    spectrum = np.abs(np.fft.rfft(signal))
    spectrum[0] = 0.0
    frequencies = np.fft.rfftfreq(len(signal), d=1.0 / fps)
    return float(frequencies[int(np.argmax(spectrum))])


def expected_simulation_result(graph_data):
    nodes = graph_data['nodes']
    edges = graph_data['edges']

    adj = {}
    for u, v in edges:
        adj.setdefault(u, []).append(v)
        adj.setdefault(v, []).append(u)

    positions = [float(i) for i in range(len(nodes))]
    velocities = [0.0] * len(nodes)
    velocities[0] = 1.0

    history = []
    for _ in range(1000):
        forces = [0.0] * len(positions)
        for node in sorted(adj.keys()):
            for neighbor in sorted(adj[node]):
                forces[node] += (positions[neighbor] - positions[node]) * 0.1

        for i in range(len(nodes)):
            velocities[i] += forces[i] * 0.01
            positions[i] += velocities[i] * 0.01
        history.append(positions[0])

    crossings = 0
    for i in range(1, len(history)):
        if history[i - 1] < 0 and history[i] >= 0:
            crossings += 1
    return crossings / 10.0


def load_simulation_module():
    assert os.path.isfile(SIM_PATH), f"File missing: {SIM_PATH}"
    spec = importlib.util.spec_from_file_location("submitted_vibration_sim", SIM_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "calculate_forces", None))
    assert callable(getattr(module, "run_simulation", None))
    return module


def post_graph(payload):
    try:
        response = requests.post(API_URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to API at {API_URL}: {exc}")
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except Exception:
        pytest.fail(f"Failed to parse JSON response: {response.text}")
    assert isinstance(data, dict)
    assert "dominant_frequency" in data, f"Missing dominant_frequency: {data}"
    value = data["dominant_frequency"]
    assert isinstance(value, (int, float)) and not isinstance(value, bool)
    assert math.isfinite(float(value))
    return float(value)


def listening_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle, None)
                for line in handle:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
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
                    pids.add(int(entry))
                    break
        except OSError:
            continue
    return pids


def test_virtual_environment_exists_and_runs_service():
    python = "/home/user/env/bin/python"
    assert os.path.isfile("/home/user/env/pyvenv.cfg"), "Virtual environment was not created"
    assert os.path.exists(python) and os.access(python, os.X_OK)
    result = subprocess.run(
        [python, "-c", "import sys, numpy, cv2; print(sys.prefix)"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "/home/user/env"

    pids = listening_pids(8080)
    assert pids, "No process is listening on port 8080"
    command_lines = []
    for pid in pids:
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as handle:
                command_lines.append(handle.read().replace(b"\0", b" ").decode(errors="replace"))
        except OSError:
            pass
    assert any("/home/user/env/" in command for command in command_lines), (
        f"The service listening on port 8080 is not running from /home/user/env: {command_lines}"
    )


def test_reference_freq_file_is_derived_from_video():
    path = "/home/user/reference_freq.txt"
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path) as handle:
        content = handle.read().strip()
    expected = video_dominant_frequency()
    assert content == f"{expected:.2f}", (
        f"Expected the video-derived value {expected:.2f} in {path}, got {content!r}"
    )


def test_force_accumulation_uses_canonical_neighbor_order():
    sim = load_simulation_module()
    positions = [0.0] * 11
    positions[3] = 1.0e16
    positions[7] = 1.0
    positions[10] = -1.0e16

    # Sorted order is 3, 7, 10. The deliberately ill-conditioned terms make
    # an unordered set reduction produce a different floating-point result.
    edge_orders = [
        [[0, 3], [0, 7], [0, 10]],
        [[0, 10], [0, 3], [0, 7]],
        [[0, 7], [0, 10], [0, 3]],
    ]
    expected = 0.0
    results = [sim.calculate_forces(list(positions), edges)[0] for edges in edge_orders]
    assert results == [expected] * len(results), (
        f"Force accumulation is not in sorted deterministic order: {results}"
    )


def test_simulation_artifact_on_multiple_topologies_and_edge_orders():
    sim = load_simulation_module()
    graphs = [
        {"nodes": [0, 1, 2], "edges": [[0, 1], [1, 2]]},
        {"nodes": [0, 1, 2, 3, 4], "edges": [[0, 1], [0, 2], [0, 3], [0, 4]]},
        {"nodes": [0, 1, 2, 3, 4, 5], "edges": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [1, 4]]},
    ]
    for graph in graphs:
        expected = expected_simulation_result(graph)
        variants = [graph, {"nodes": graph["nodes"], "edges": list(reversed(graph["edges"]))}]
        results = []
        for variant in variants:
            results.extend(float(sim.run_simulation(variant)) for _ in range(3))
        assert all(math.isfinite(value) for value in results)
        assert all(value == expected for value in results), (
            f"Simulation is non-deterministic or incorrect for {graph}: {results}, expected {expected}"
        )


def test_default_graph_is_deterministic_and_agrees_with_reference():
    sim = load_simulation_module()
    with open(DEFAULT_GRAPH_PATH) as handle:
        graph = json.load(handle)
    reference = video_dominant_frequency()
    variants = [graph, {"nodes": graph["nodes"], "edges": list(reversed(graph["edges"]))}]
    local_results = [float(sim.run_simulation(item)) for item in variants for _ in range(3)]
    assert len(set(local_results)) == 1, f"Default simulation is not deterministic: {local_results}"
    assert abs(local_results[0] - reference) <= 0.05, (
        f"Default simulation frequency {local_results[0]} does not closely match reference {reference}"
    )
    api_result = post_graph(graph)
    assert abs(api_result - local_results[0]) < 1e-5


def test_api_simulate_endpoint_on_unseen_topologies():
    # Preserve the original five-node-cycle assertion.
    payloads = [{
        "nodes": [0, 1, 2, 3, 4],
        "edges": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 0]],
    }]

    # Generate additional topologies at verification time rather than relying
    # on one hard-coded request that can be answered by a constant endpoint.
    rng = secrets.SystemRandom()
    for n in (5, 6, 7):
        edges = [[i, i + 1] for i in range(n - 1)]
        candidates = [[i, j] for i in range(n) for j in range(i + 2, n) if [i, j] not in edges]
        rng.shuffle(candidates)
        edges.extend(candidates[: max(1, n // 2)])
        rng.shuffle(edges)
        payloads.append({"nodes": list(range(n)), "edges": edges})

    for payload in payloads:
        expected = expected_simulation_result(payload)
        actual = post_graph(payload)
        assert abs(actual - expected) < 1e-5, (
            f"Expected dominant_frequency {expected} for {payload}, got {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
