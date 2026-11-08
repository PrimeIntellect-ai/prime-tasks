#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess
import xml.etree.ElementTree as ET

import pytest

HOME = "/home/user"
ENGINE = f"{HOME}/sim_engine"
OUTPUT = f"{HOME}/sim_output.csv"
REFERENCE = f"{HOME}/reference_data.csv"
LOG = f"{HOME}/evaluation.log"
PLOT_SCRIPT = f"{HOME}/plot_data.py"
PLOT = f"{HOME}/trajectory_plot.svg"


def read_csv(path):
    assert os.path.isfile(path), f"{path} does not exist."
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["time", "node1_x", "node1_v"], \
            f"{path} header is incorrect: {reader.fieldnames}"
        rows = []
        for line_no, row in enumerate(reader, 2):
            try:
                values = tuple(float(row[k]) for k in reader.fieldnames)
            except (TypeError, ValueError):
                pytest.fail(f"Non-numeric data in {path} at line {line_no}: {row}")
            assert all(math.isfinite(v) for v in values), \
                f"Non-finite data in {path} at line {line_no}: {row}"
            rows.append(values)
    assert rows, f"{path} contains no data rows."
    return rows


def matching_mse(sim_rows, ref_rows):
    ref = {round(t, 9): x for t, x, _ in ref_rows}
    matched = [(x, ref[round(t, 9)]) for t, x, _ in sim_rows if round(t, 9) in ref]
    assert len(matched) == len(ref_rows), \
        f"Simulation has {len(matched)} of {len(ref_rows)} required reference time steps."
    return sum((x - expected) ** 2 for x, expected in matched) / len(matched)


def test_integrator_fixed_and_simulation_reproducible():
    integrator_path = f"{ENGINE}/src/integrator.rs"
    assert os.path.isfile(integrator_path), f"{integrator_path} does not exist."
    with open(integrator_path) as f:
        content = f.read()

    # Retain the original source assertions.
    assert "error / tolerance" not in content, \
        "The bug 'error / tolerance' is still present in integrator.rs."
    assert "tolerance / error" in content, \
        "The fix 'tolerance / error' was not found in integrator.rs."

    # Compile and execute the submitted Rust project rather than trusting artifacts.
    proc = subprocess.run(
        ["cargo", "run", "--quiet"], cwd=ENGINE, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert proc.returncode == 0, f"Simulation failed:\n{proc.stderr}"
    with open("/tmp/fresh_sim_output.csv", "w") as f:
        f.write(proc.stdout)

    fresh = read_csv("/tmp/fresh_sim_output.csv")
    submitted = read_csv(OUTPUT)
    assert submitted == fresh, "sim_output.csv is not the output of the current simulation."

    reference = read_csv(REFERENCE)
    mse = matching_mse(fresh, reference)
    assert mse < 0.1, f"Recomputed MSE is too high: {mse}"


def test_evaluation_log_is_exact_recomputed_mse():
    sim = read_csv(OUTPUT)
    reference = read_csv(REFERENCE)
    expected = matching_mse(sim, reference)

    assert os.path.isfile(LOG), f"{LOG} does not exist."
    with open(LOG) as f:
        content = f.read().strip()
    match = re.fullmatch(r"MSE:\s*([0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?)", content)
    assert match is not None, f"Expected exact format 'MSE: <value>', got: {content}"
    reported = float(match.group(1))
    assert math.isfinite(reported) and reported >= 0, f"Invalid MSE: {reported}"
    assert math.isclose(reported, expected, rel_tol=1e-6, abs_tol=1e-10), \
        f"Reported MSE {reported} does not match recomputed MSE {expected}."
    assert reported < 0.1, f"MSE is suspiciously high: {reported}"


def test_plot_script_executes_and_generates_svg():
    assert os.path.isfile(PLOT_SCRIPT), f"Plotting script {PLOT_SCRIPT} does not exist."

    # Remove the old artifact so success requires this submitted script to recreate it.
    if os.path.lexists(PLOT):
        os.remove(PLOT)
    proc = subprocess.run(
        ["python3", PLOT_SCRIPT], cwd=HOME, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert proc.returncode == 0, f"Plot script failed:\n{proc.stderr}"
    assert os.path.isfile(PLOT) and not os.path.islink(PLOT), \
        f"Plot script did not create a regular file at {PLOT}."
    assert os.path.getsize(PLOT) > 1000, "Generated SVG is implausibly small."
    try:
        root = ET.parse(PLOT).getroot()
    except ET.ParseError as exc:
        pytest.fail(f"Generated plot is not valid XML/SVG: {exc}")
    assert root.tag.lower().endswith("svg"), "Generated plot root element is not SVG."
    elements = list(root.iter())
    assert len(elements) > 10, "Generated SVG contains too little graphical content."
    # Matplotlib line plots include multiple path/polyline elements.
    graphical = [e for e in elements if e.tag.lower().split("}")[-1] in {"path", "polyline"}]
    assert len(graphical) >= 2, "SVG does not contain two plotted trajectory graphics."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
