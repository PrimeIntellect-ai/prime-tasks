#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import shutil
import stat
import subprocess
import tempfile

import numpy as np


def run(cmd, **kwargs):
    return subprocess.run(cmd, timeout=45, check=True, **kwargs)


def read_results():
    path = "/home/user/results.log"
    assert os.path.isfile(path), f"Missing file: {path}"
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_simulate_script_fixed():
    """Keep the original source-order assertion."""
    script_path = "/home/user/simulate.py"
    assert os.path.isfile(script_path), f"Missing file: {script_path}"

    with open(script_path, "r") as f:
        content = f.read()

    pos_idx = content.find("pos = pos + vel")
    if pos_idx == -1:
        pos_match = re.search(r'pos\s*\+=\s*vel\s*\*\s*dt|pos\s*=\s*pos\s*\+\s*vel\s*\*\s*dt', content)
        assert pos_match is not None, "Could not find position update in simulate.py"
        pos_idx = pos_match.start()

    vel_idx = content.find("vel = vel + acc")
    if vel_idx == -1:
        vel_match = re.search(r'vel\s*\+=\s*acc\s*\*\s*dt|vel\s*=\s*vel\s*\+\s*acc\s*\*\s*dt', content)
        assert vel_match is not None, "Could not find velocity update in simulate.py"
        vel_idx = vel_match.start()

    assert vel_idx < pos_idx, "simulate.py must update velocity BEFORE position (Symplectic Euler)."


def test_scripts_exist():
    assert os.path.isfile("/home/user/analyze.py"), "/home/user/analyze.py is missing."
    assert os.path.isfile("/home/user/pipeline.sh"), "/home/user/pipeline.sh is missing."


def test_simulation_behavior():
    """Execute simulate.py at an unpredictable step size and compare with Symplectic Euler."""
    topology = secrets.choice(["ring", "star"])
    dt = secrets.randbelow(51) / 10000.0 + 0.0075
    dt_arg = f"{dt:.4f}"
    dt = float(dt_arg)

    completed = run(
        ["python3", "/home/user/simulate.py", topology, dt_arg],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        actual = np.loadtxt(completed.stdout.splitlines())
    except Exception as exc:
        raise AssertionError(f"simulate.py did not produce valid tabular numeric output: {exc}")

    n = 5
    adjacency = np.zeros((n, n))
    if topology == "ring":
        for i in range(n):
            adjacency[i, (i + 1) % n] = 1
            adjacency[(i + 1) % n, i] = 1
    else:
        for i in range(1, n):
            adjacency[0, i] = 1
            adjacency[i, 0] = 1
    laplacian = np.diag(adjacency.sum(axis=1)) - adjacency

    pos = np.zeros(n)
    vel = np.zeros(n)
    pos[0] = 1.0
    rows = []
    for i in range(int(20.0 / dt)):
        rows.append(np.concatenate(([i * dt], pos.copy())))
        acc = -20.0 * np.dot(laplacian, pos)
        vel = vel + acc * dt
        pos = pos + vel * dt
    expected = np.asarray(rows)

    assert actual.shape == expected.shape, "simulate.py must emit one time plus five positions for the full 20-second duration"
    assert np.isfinite(actual).all(), "Simulation output contains NaN or infinite values"
    # The supplied simulator formats every value to four decimal places.
    assert np.allclose(actual, expected, rtol=0, atol=5.1e-5), "Simulation output does not implement the requested Symplectic Euler model"


def test_analyzer_behavior():
    """Exercise analyze.py on a generated signal whose FFT answer is derived here."""
    n = 1024
    dt = (secrets.randbelow(31) + 80) / 10000.0
    target_bin = secrets.randbelow(45) + 20
    distractor_bin = target_bin + secrets.randbelow(25) + 10
    t = np.arange(n) * dt
    node0 = 4.0 + np.sin(2 * np.pi * target_bin * np.arange(n) / n)
    node0 += 0.15 * np.sin(2 * np.pi * (target_bin + 3) * np.arange(n) / n)
    node1 = 10.0 * np.sin(2 * np.pi * distractor_bin * np.arange(n) / n)
    table = np.column_stack((t, node0, node1, np.zeros(n), np.zeros(n), np.zeros(n)))
    input_text = "\n".join(" ".join(f"{v:.10f}" for v in row) for row in table) + "\n"

    completed = run(
        ["python3", "/home/user/analyze.py"],
        input=input_text,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    output = completed.stdout.strip()
    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", output), "analyze.py must print only one floating-point frequency"
    value = float(output)
    expected = target_bin / (n * dt)
    assert math.isfinite(value)
    assert abs(value - expected) <= 1e-4, f"Expected dominant node-0 frequency {expected}, got {value}"


def test_pipeline_executes_both_tools_and_computes_match():
    """Instrument both dependencies, then run the real pipeline again for the final log."""
    simulate_path = "/home/user/simulate.py"
    analyze_path = "/home/user/analyze.py"
    pipeline_path = "/home/user/pipeline.sh"

    with tempfile.TemporaryDirectory(prefix="pipeline_check_") as td:
        sim_backup = os.path.join(td, "simulate_original.py")
        analyze_backup = os.path.join(td, "analyze_original.py")
        trace_path = os.path.join(td, "trace.log")
        shutil.copy2(simulate_path, sim_backup)
        shutil.copy2(analyze_path, analyze_backup)

        sim_wrapper = f'''#!/usr/bin/env python3
import os, sys
with open({trace_path!r}, "a") as f:
    f.write("SIM\\t" + "\\t".join(sys.argv[1:]) + "\\n")
os.execv(sys.executable, [sys.executable, {sim_backup!r}] + sys.argv[1:])
'''
        # This wrapper consumes the piped simulation data, identifies which
        # dt=0.01 topology produced it, and emits challenge frequencies. The
        # closer topology is intentionally star, so a hardcoded 'ring' fails.
        analyze_wrapper = f'''#!/usr/bin/env python3
import sys
text = sys.stdin.read()
lines = [line.split() for line in text.splitlines() if line.strip()]
if len(lines) < 2 or len(lines[1]) < 2:
    sys.exit(3)
x0_second = float(lines[1][1])
kind = "star" if x0_second < 0.994 else "ring"
with open({trace_path!r}, "a") as f:
    f.write("AN\\t" + kind + "\\n")nvalue = 1.41 if kind == "star" else 1.80
print(value)
'''.replace('\\nnvalue', '\\nvalue')

        try:
            with open(simulate_path, "w") as f:
                f.write(sim_wrapper)
            with open(analyze_path, "w") as f:
                f.write(analyze_wrapper)
            os.chmod(simulate_path, 0o755)
            os.chmod(analyze_path, 0o755)
            if os.path.exists("/home/user/results.log"):
                os.remove("/home/user/results.log")

            run(["bash", pipeline_path], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            challenge_lines = read_results()
            assert challenge_lines == [
                "Star frequency: 1.41",
                "Ring frequency: 1.80",
                "Hypothesis match: star",
            ], "pipeline.sh must use analyzer outputs, round them, and choose the topology closest to 1.42"

            with open(trace_path, "r") as f:
                trace = [line.strip().split("\t") for line in f if line.strip()]
            sim_calls = [parts for parts in trace if parts[0] == "SIM"]
            assert any(len(parts) == 3 and parts[1] == "star" and abs(float(parts[2]) - 0.01) < 1e-12 for parts in sim_calls), "pipeline.sh did not run star simulation with dt=0.01"
            assert any(len(parts) == 3 and parts[1] == "ring" and abs(float(parts[2]) - 0.01) < 1e-12 for parts in sim_calls), "pipeline.sh did not run ring simulation with dt=0.01"
            analyzed = {parts[1] for parts in trace if len(parts) == 2 and parts[0] == "AN"}
            assert {"star", "ring"}.issubset(analyzed), "pipeline.sh must pipe both simulation outputs through analyze.py"
        finally:
            shutil.copy2(sim_backup, simulate_path)
            shutil.copy2(analyze_backup, analyze_path)

    # Generate the required final artifact using the agent's real scripts.
    if os.path.exists("/home/user/results.log"):
        os.remove("/home/user/results.log")
    run(["bash", pipeline_path], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def test_results_log():
    """Keep the original result assertions and enforce the requested exact layout."""
    lines = read_results()
    assert len(lines) >= 3, "results.log must contain at least 3 lines of output."

    star_line = lines[0]
    ring_line = lines[1]
    match_line = lines[2]

    star_match = re.search(r'Star frequency:\s*([0-9.]+)', star_line, re.IGNORECASE)
    assert star_match is not None, "Line 1 of results.log must be 'Star frequency: <value>'"
    star_val = float(star_match.group(1))
    assert 1.58 <= star_val <= 1.60, f"Star frequency {star_val} is out of expected range (1.58-1.60)."

    ring_match = re.search(r'Ring frequency:\s*([0-9.]+)', ring_line, re.IGNORECASE)
    assert ring_match is not None, "Line 2 of results.log must be 'Ring frequency: <value>'"
    ring_val = float(ring_match.group(1))
    assert 1.41 <= ring_val <= 1.44, f"Ring frequency {ring_val} is out of expected range (1.41-1.44)."

    assert "ring" in match_line.lower(), "Line 3 of results.log must indicate 'ring' as the hypothesis match."
    assert "Hypothesis match:" in match_line, "Line 3 must start with 'Hypothesis match:'"

    assert len(lines) == 3, "results.log must contain exactly the three requested lines"
    assert re.fullmatch(r"Star frequency: [0-9]+\.[0-9]{2}", star_line)
    assert re.fullmatch(r"Ring frequency: [0-9]+\.[0-9]{2}", ring_line)
    assert match_line == "Hypothesis match: ring"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
