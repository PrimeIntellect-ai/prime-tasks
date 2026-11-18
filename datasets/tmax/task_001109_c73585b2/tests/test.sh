#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import math
import os
import struct
import subprocess

import matplotlib.image as mpimg

SIMULATE_PATH = "/home/user/simulate.py"
JSON_PATH = "/home/user/final_temperatures.json"
PLOT_PATH = "/home/user/thermal_plot.png"


def load_simulate():
    spec = importlib.util.spec_from_file_location("submitted_simulate", SIMULATE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def reference_derivatives(temps, edges, alpha):
    deriv = {node: 0.0 for node in temps}
    for u, v in edges:
        deriv[u] += temps[v] - temps[u]
        deriv[v] += temps[u] - temps[v]
    return {node: value * alpha for node, value in deriv.items()}


def reference_step(temps, edges, alpha, dt):
    deriv = reference_derivatives(temps, edges, alpha)
    return {node: temps[node] + deriv[node] * dt for node in temps}


def reference_integrate(nodes, edges, initial_temps, alpha, t_end):
    temps = initial_temps.copy()
    t = 0.0
    dt = 0.1
    tol = 1e-4
    while t < t_end:
        if t + dt > t_end:
            dt = t_end - t
        full = reference_step(temps, edges, alpha, dt)
        half = reference_step(temps, edges, alpha, dt / 2.0)
        half = reference_step(half, edges, alpha, dt / 2.0)
        error = max(abs(full[n] - half[n]) for n in nodes)
        if error > tol:
            dt = dt / 2.0
            continue
        temps = half
        t += dt
        if error < tol / 10.0:
            dt *= 1.5
    return temps


def assert_temperatures_close(actual, expected):
    assert set(actual) == set(expected)
    for node in expected:
        assert math.isfinite(float(actual[node])), f"Non-finite temperature for node {node}"
        assert math.isclose(float(actual[node]), expected[node], rel_tol=1e-10, abs_tol=1e-10), (
            f"Incorrect temperature for node {node}: got {actual[node]}, expected {expected[node]}"
        )


def test_01_simulation_executes_and_regenerates_outputs():
    assert os.path.isfile(SIMULATE_PATH), f"File {SIMULATE_PATH} does not exist."
    for path in (JSON_PATH, PLOT_PATH):
        if os.path.exists(path):
            os.remove(path)
    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    result = subprocess.run(
        ["python3", SIMULATE_PATH],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"simulate.py did not complete successfully (exit {result.returncode}).\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(JSON_PATH), f"Expected file {JSON_PATH} does not exist. Did you export the temperatures?"
    assert os.path.isfile(PLOT_PATH), f"Expected plot {PLOT_PATH} does not exist. Did you save the plot?"


def test_02_refine_mesh_behavior():
    module = load_simulate()
    nodes = [0, 1, 2, 3]
    edges = [[0, 1], [1, 2], [2, 3]]
    initial = {0: 100.0, 1: 0.0, 2: 0.0, 3: 10.0}
    result = module.refine_mesh(nodes.copy(), [e.copy() for e in edges], initial.copy())
    assert isinstance(result, tuple) and len(result) == 3, "refine_mesh must return nodes, edges, initial_temps"
    refined_nodes, refined_edges, refined_temps = result
    assert set(refined_nodes) == set(range(7)), f"Incorrect refined nodes: {refined_nodes}"
    expected_edges = {(0, 4), (4, 1), (1, 5), (5, 2), (2, 6), (6, 3)}
    assert {tuple(edge) for edge in refined_edges} == expected_edges, f"Incorrect refined edges: {refined_edges}"
    assert len(refined_edges) == 6, "Each original edge must be replaced by exactly two edges"
    expected_initial = {0: 100.0, 1: 0.0, 2: 0.0, 3: 10.0, 4: 50.0, 5: 0.0, 6: 5.0}
    assert set(refined_temps) == set(expected_initial)
    for node, value in expected_initial.items():
        assert float(refined_temps[node]) == value, f"Incorrect initial temperature for node {node}"

    # Exercise nonconsecutive IDs and nonzero midpoint temperatures.
    n2, e2, t2 = module.refine_mesh(
        [2, 5, 9], [[2, 9], [9, 5]], {2: -4.0, 5: 8.0, 9: 10.0}
    )
    assert set(n2) == {2, 5, 9, 10, 11}
    assert {tuple(edge) for edge in e2} == {(2, 10), (10, 9), (9, 11), (11, 5)}
    assert len(e2) == 4
    assert float(t2[10]) == 3.0
    assert float(t2[11]) == 9.0


def test_03_adaptive_integrator_matches_correct_step_rejection_logic():
    module = load_simulate()
    cases = [
        ([0, 1], [[0, 1]], {0: 100.0, 1: 0.0}, 0.5, 0.5),
        ([0, 1, 2], [[0, 1], [1, 2]], {0: -5.0, 1: 20.0, 2: 7.0}, 0.3, 0.37),
    ]
    for nodes, edges, initial, alpha, t_end in cases:
        expected = reference_integrate(nodes, edges, initial, alpha, t_end)
        actual = module.adaptive_integrate(nodes, edges, initial, alpha, t_end)
        assert_temperatures_close(actual, expected)


def test_04_final_temperatures_json():
    assert os.path.isfile(JSON_PATH), f"Expected file {JSON_PATH} does not exist. Did you export the temperatures?"
    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{JSON_PATH} is not valid JSON."

    assert isinstance(data, dict), "Final temperatures must be a JSON object."
    assert len(data) == 7, f"Expected exactly 7 nodes after refinement, but found {len(data)} in {JSON_PATH}."
    assert "0" in data, "Node '0' missing from final temperatures."
    assert "1" in data, "Node '1' missing from final temperatures."
    assert set(data) == {str(i) for i in range(7)}, f"Unexpected node IDs in {JSON_PATH}."

    t0 = float(data["0"])
    t1 = float(data["1"])
    assert t0 < 100.0, f"Node 0 did not cool down as expected. Final temp: {t0}"
    assert t1 > 0.0, f"Node 1 did not warm up as expected. Final temp: {t1}"

    nodes = list(range(7))
    edges = [[0, 4], [4, 1], [1, 5], [5, 2], [2, 6], [6, 3]]
    initial = {0: 100.0, 1: 0.0, 2: 0.0, 3: 10.0, 4: 50.0, 5: 0.0, 6: 5.0}
    expected = reference_integrate(nodes, edges, initial, 0.5, 0.5)
    actual = {int(key): value for key, value in data.items()}
    assert_temperatures_close(actual, expected)


def test_05_thermal_plot_is_valid_png():
    assert os.path.isfile(PLOT_PATH), f"Expected plot {PLOT_PATH} does not exist. Did you save the plot?"
    assert os.path.getsize(PLOT_PATH) > 0, f"Plot {PLOT_PATH} is empty."
    with open(PLOT_PATH, "rb") as f:
        header = f.read(24)
    assert header[:8] == b"\x89PNG\r\n\x1a\n", "thermal_plot.png is not a PNG file"
    assert header[12:16] == b"IHDR", "thermal_plot.png has no valid PNG IHDR"
    width, height = struct.unpack(">II", header[16:24])
    assert width > 1 and height > 1, "thermal_plot.png has invalid dimensions"
    image = mpimg.imread(PLOT_PATH)
    assert image.size > 0 and image.shape[0] == height and image.shape[1] == width
    assert float(image.max()) > float(image.min()), "thermal_plot.png contains no visible plotted content"


def test_06_buggy_literal_removed():
    assert os.path.isfile(SIMULATE_PATH), f"File {SIMULATE_PATH} does not exist."
    with open(SIMULATE_PATH, "r") as f:
        content = f.read()
    assert "dt = dt * 2.0" not in content, "The bug 'dt = dt * 2.0' is still present in simulate.py. It should be changed to reduce the step size."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
