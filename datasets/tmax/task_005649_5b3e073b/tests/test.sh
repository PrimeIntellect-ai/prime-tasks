#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import subprocess
from pathlib import Path

import pytest

VENV_PYTHON = "/home/user/sim_env/bin/python"
SCRIPT_PATH = "/home/user/analyze_mesh.py"
DATA_PATH = Path("/home/user/mesh_data.csv")
TOTAL_PATH = Path("/home/user/total_volume.txt")
CI_PATH = Path("/home/user/bootstrap_ci.txt")


def test_venv_exists():
    """Check that the Python virtual environment and required packages exist."""
    assert os.path.isfile(VENV_PYTHON), (
        f"Virtual environment Python executable not found at {VENV_PYTHON}."
    )
    subprocess.run(
        [VENV_PYTHON, "-c", "import numpy; import scipy; import scipy.stats"],
        check=True,
        timeout=30,
    )


def test_script_exists():
    """Check that the analysis script exists."""
    assert os.path.isfile(SCRIPT_PATH), f"Analysis script not found at {SCRIPT_PATH}."


def test_script_contains_required_calls():
    """Check that the requested APIs and literal bootstrap settings are present."""
    source = Path(SCRIPT_PATH).read_text()
    tree = ast.parse(source, filename=SCRIPT_PATH)

    has_math_fsum = any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and isinstance(node.func.value, ast.Name)
        and node.func.value.id == "math"
        and node.func.attr == "fsum"
        for node in ast.walk(tree)
    )
    assert has_math_fsum, "analyze_mesh.py must call math.fsum()."

    valid_bootstrap_call = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        is_bootstrap = (
            isinstance(node.func, ast.Name) and node.func.id == "bootstrap"
        ) or (
            isinstance(node.func, ast.Attribute) and node.func.attr == "bootstrap"
        )
        if not is_bootstrap:
            continue

        kwargs = {kw.arg: kw.value for kw in node.keywords if kw.arg is not None}
        try:
            values = {name: ast.literal_eval(value) for name, value in kwargs.items()}
        except (ValueError, TypeError):
            continue
        if (
            values.get("n_resamples") == 10000
            and values.get("vectorized") is True
            and values.get("method") == "BCa"
            and values.get("random_state") == 42
        ):
            valid_bootstrap_call = True
            break

    assert valid_bootstrap_call, (
        "scipy.stats.bootstrap must be called with n_resamples=10000, "
        "vectorized=True, method='BCa', and random_state=42."
    )


def _expected_outputs():
    code = r'''import math
import numpy as np
from scipy.stats import bootstrap

values = []
with open("/home/user/mesh_data.csv", "r") as f:
    next(f)
    for line in f:
        if not line.strip():
            continue
        volume = float(line.split(",")[1])
        if volume < 0.05:
            values.append(volume)

total = math.fsum(values)
result = bootstrap(
    (np.asarray(values, dtype=float),),
    np.mean,
    n_resamples=10000,
    vectorized=True,
    method="BCa",
    random_state=42,
)
print(f"{total:.8f}")
print(f"{result.confidence_interval.low:.8f},{result.confidence_interval.high:.8f}")
'''
    output = subprocess.check_output(
        [VENV_PYTHON, "-c", code], text=True, timeout=120
    ).splitlines()
    assert len(output) == 2
    return output[0], output[1]


def _install_trace_hook(directory: Path):
    hook = directory / "sitecustomize.py"
    hook.write_text(r'''import atexit
import json
import math
import os
import scipy.stats

_events = {"fsum_calls": 0, "bootstrap_calls": []}
_original_fsum = math.fsum
_original_bootstrap = scipy.stats.bootstrap

def _fsum(values):
    _events["fsum_calls"] += 1
    return _original_fsum(values)

def _bootstrap(*args, **kwargs):
    _events["bootstrap_calls"].append({
        "n_resamples": kwargs.get("n_resamples"),
        "vectorized": kwargs.get("vectorized"),
        "method": kwargs.get("method"),
        "random_state": kwargs.get("random_state"),
    })
    return _original_bootstrap(*args, **kwargs)

math.fsum = _fsum
scipy.stats.bootstrap = _bootstrap

@atexit.register
def _write_trace():
    path = os.environ.get("ANALYSIS_TRACE_LOG")
    if path:
        with open(path, "w") as f:
            json.dump(_events, f)
''')


def _run_script(trace_dir: Path, trace_log: Path):
    env = os.environ.copy()
    env["PYTHONPATH"] = str(trace_dir) + (
        os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
    )
    env["ANALYSIS_TRACE_LOG"] = str(trace_log)
    subprocess.run(
        [VENV_PYTHON, SCRIPT_PATH],
        check=True,
        timeout=180,
        env=env,
        cwd="/home/user",
    )
    assert trace_log.is_file(), "The executed analysis did not produce an API trace."
    return json.loads(trace_log.read_text())


def _assert_required_runtime_calls(events):
    assert events.get("fsum_calls", 0) >= 1, (
        "The executed analysis must use math.fsum() for the refined-cell total."
    )
    required = {
        "n_resamples": 10000,
        "vectorized": True,
        "method": "BCa",
        "random_state": 42,
    }
    assert required in events.get("bootstrap_calls", []), (
        "The executed analysis must call scipy.stats.bootstrap with the mandated parameters."
    )


def test_analysis_pipeline_executes_on_derived_input(tmp_path):
    """Run the submitted script on unseen data and derive the expected answers."""
    original_data = DATA_PATH.read_bytes()
    trace_dir = tmp_path / "trace_hook"
    trace_dir.mkdir()
    _install_trace_hook(trace_dir)

    refined = [0.00037 + i * 0.00071 for i in range(60)]
    rows = ["domain_id,cell_volume"]
    rows.extend(f"{i % 7},{value:.10f}" for i, value in enumerate(refined))
    rows.extend(["1,0.0500000000", "2,0.1000000000", "3,1.2500000000"])

    alternate_total = alternate_ci = None
    alternate_events = None
    try:
        DATA_PATH.write_text("\n".join(rows) + "\n")
        alternate_total, alternate_ci = _expected_outputs()
        TOTAL_PATH.unlink(missing_ok=True)
        CI_PATH.unlink(missing_ok=True)
        alternate_events = _run_script(
            trace_dir, tmp_path / "alternate_trace.json"
        )
        actual_total = TOTAL_PATH.read_text().strip()
        actual_ci = CI_PATH.read_text().strip()
    finally:
        DATA_PATH.write_bytes(original_data)
        TOTAL_PATH.unlink(missing_ok=True)
        CI_PATH.unlink(missing_ok=True)
        original_events = _run_script(
            trace_dir, tmp_path / "original_trace.json"
        )

    assert actual_total == alternate_total, (
        f"Expected alternate-data total {alternate_total}, but got {actual_total}."
    )
    assert actual_ci == alternate_ci, (
        f"Expected alternate-data bootstrap CI {alternate_ci}, but got {actual_ci}."
    )
    _assert_required_runtime_calls(alternate_events)
    _assert_required_runtime_calls(original_events)


def test_total_volume():
    """Check that the total volume of refined cells is calculated correctly."""
    data_path = "/home/user/mesh_data.csv"
    assert os.path.isfile(data_path), f"Data file {data_path} is missing."

    refined_vols = []
    with open(data_path, "r") as f:
        header = f.readline()
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            if len(parts) >= 2:
                vol = float(parts[1])
                if vol < 0.05:
                    refined_vols.append(vol)

    expected_total_vol = math.fsum(refined_vols)
    expected_str = f"{expected_total_vol:.8f}"

    output_path = "/home/user/total_volume.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} is missing."

    with open(output_path, "r") as f:
        actual_str = f.read().strip()

    assert actual_str == expected_str, (
        f"Expected total volume {expected_str}, but got {actual_str}."
    )


def test_bootstrap_ci():
    """Check that the bootstrap confidence interval is calculated correctly."""
    output_path = "/home/user/bootstrap_ci.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} is missing."

    with open(output_path, "r") as f:
        actual_str = f.read().strip()

    expected_str = "0.02462319,0.02542472"
    assert actual_str == expected_str, (
        f"Expected bootstrap CI {expected_str}, but got {actual_str}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
