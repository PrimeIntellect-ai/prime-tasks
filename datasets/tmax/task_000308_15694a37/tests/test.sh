#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import shutil
import signal
import stat
import subprocess
import tempfile
import time

import h5py
import numpy as np
import pytest

ENGINE = "/app/sim_engine"
HOME = "/home/user"
RUN_RECORDS = []


@pytest.fixture(scope="session", autouse=True)
def execute_optimizer():
    """Run the submitted optimizer and record its simulator calls."""
    assert os.path.isfile(ENGINE), f"Simulation engine not found at {ENGINE}"
    assert os.access(ENGINE, os.X_OK), f"Simulation engine is not executable: {ENGINE}"
    assert os.path.isfile(f"{HOME}/optimize.py"), "Optimization script not found"

    workdir = tempfile.mkdtemp(prefix="verify_optimizer_")
    real_engine = os.path.join(workdir, "sim_engine.real")
    log_path = os.path.join(workdir, "calls.jsonl")
    wrapper_tmp = os.path.join(workdir, "sim_engine.wrapper")
    shutil.copy2(ENGINE, real_engine)
    os.chmod(real_engine, 0o755)
    with open(log_path, "w"):
        pass
    os.chmod(log_path, 0o666)

    wrapper = f'''#!/usr/bin/python3
import json, os, subprocess, sys, time
real = {real_engine!r}
log = {log_path!r}
start = time.time_ns()
# Make independently dispatched evaluations overlap long enough to observe.
time.sleep(0.02)
rc = 127
try:
    rc = subprocess.call([real] + sys.argv[1:])
finally:
    record = {{"pid": os.getpid(), "start": start, "end": time.time_ns(), "args": sys.argv[1:]}}
    fd = os.open(log, os.O_WRONLY | os.O_APPEND)
    try:
        os.write(fd, (json.dumps(record, separators=(",", ":")) + "\\n").encode())
    finally:
        os.close(fd)
sys.exit(rc)
'''

    proc = None
    try:
        with open(wrapper_tmp, "w") as f:
            f.write(wrapper)
        os.chmod(wrapper_tmp, 0o755)
        os.replace(wrapper_tmp, ENGINE)

        # A pre-existing answer must not allow the script to skip doing the work.
        try:
            os.remove(f"{HOME}/best_params.json")
        except FileNotFoundError:
            pass

        proc = subprocess.Popen(
            ["runuser", "-u", "user", "--", "python3", f"{HOME}/optimize.py"],
            cwd=HOME,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
        )
        try:
            output, _ = proc.communicate(timeout=180)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            output, _ = proc.communicate()
            pytest.fail(f"optimize.py did not finish within 180 seconds. Output:\n{output[-4000:]}")
        assert proc.returncode == 0, f"optimize.py exited with {proc.returncode}. Output:\n{output[-4000:]}"

        with open(log_path) as f:
            for line in f:
                if line.strip():
                    RUN_RECORDS.append(json.loads(line))
    finally:
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        # Restore the real simulation binary before independently scoring the result.
        if os.path.exists(real_engine):
            os.replace(real_engine, ENGINE)
        shutil.rmtree(workdir, ignore_errors=True)


def test_obs_data_h5_exists():
    path = "/home/user/obs_data.h5"
    assert os.path.exists(path), f"HDF5 file not found at {path}"
    assert os.path.isfile(path), f"{path} is not a file"


def test_optimize_script_exists():
    path = "/home/user/optimize.py"
    assert os.path.exists(path), f"Optimization script not found at {path}"
    assert os.path.isfile(path), f"{path} is not a file"


def test_best_params_json_exists():
    path = "/home/user/best_params.json"
    assert os.path.exists(path), f"Output file not found at {path}"
    assert os.path.isfile(path), f"{path} is not a file"


def test_hdf5_is_correct_reshape_of_raw_data():
    expected = np.empty((100, 100), dtype=np.float64)
    seen = np.zeros((100, 100), dtype=bool)
    with open(f"{HOME}/raw_data.csv", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames is not None
        assert {"x_index", "y_index", "measurement"}.issubset(reader.fieldnames)
        for row in reader:
            i, j = int(row["x_index"]), int(row["y_index"])
            assert 0 <= i < 100 and 0 <= j < 100
            assert not seen[i, j], f"Duplicate raw-data coordinate ({i}, {j})"
            expected[i, j] = float(row["measurement"])
            seen[i, j] = True
    assert seen.all(), "raw_data.csv does not contain every 100x100 coordinate"

    with h5py.File(f"{HOME}/obs_data.h5", "r") as h5:
        assert "grid_data" in h5, "HDF5 dataset 'grid_data' is missing"
        dataset = h5["grid_data"]
        assert dataset.shape == (100, 100), f"grid_data has shape {dataset.shape}, expected (100, 100)"
        actual = dataset[...]
    assert np.issubdtype(actual.dtype, np.number), "grid_data must be numeric"
    assert np.isfinite(actual).all(), "grid_data contains non-finite values"
    np.testing.assert_allclose(actual, expected, rtol=1e-12, atol=1e-12)


def test_optimizer_performed_multiple_parallel_evaluations():
    valid = []
    triples = set()
    for record in RUN_RECORDS:
        args = record.get("args", [])
        if len(args) != 4:
            continue
        try:
            triple = tuple(float(v) for v in args[1:])
            start, end = int(record["start"]), int(record["end"])
        except (TypeError, ValueError, KeyError):
            continue
        if all(math.isfinite(v) for v in triple) and end >= start:
            valid.append((start, end, int(record["pid"])))
            triples.add(tuple(round(v, 12) for v in triple))

    assert len(triples) >= 8, f"optimize.py explored only {len(triples)} distinct parameter triples"

    overlap = False
    for i, (s1, e1, pid1) in enumerate(valid):
        for s2, e2, pid2 in valid[i + 1:]:
            if pid1 != pid2 and max(s1, s2) < min(e1, e2):
                overlap = True
                break
        if overlap:
            break
    assert overlap, "Simulator evaluations were not executed in parallel"


def test_best_params_structure_and_metric():
    path = "/home/user/best_params.json"
    assert os.path.exists(path), f"Output file not found at {path}"

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File at {path} is not valid JSON")

    required_keys = {"p1", "p2", "p3", "energy"}
    missing_keys = required_keys - set(data.keys())
    assert not missing_keys, f"JSON is missing required keys: {missing_keys}"

    energy = data["energy"]
    assert isinstance(energy, (int, float)), f"Energy must be a number, got {type(energy)}"

    threshold = 5.0
    assert energy <= threshold, f"Metric threshold failed: energy value {energy} is not <= {threshold}"

    values = []
    for key in ("p1", "p2", "p3"):
        value = data[key]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), f"{key} must be numeric"
        assert math.isfinite(value), f"{key} must be finite"
        assert -10.0 <= value <= 10.0, f"{key}={value} is outside [-10.0, 10.0]"
        values.append(float(value))
    assert not isinstance(energy, bool) and math.isfinite(float(energy)), "Energy must be finite"

    result = subprocess.run(
        [ENGINE, f"{HOME}/obs_data.h5", *(repr(v) for v in values)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"sim_engine failed: {result.stdout}\n{result.stderr}"
    try:
        actual_energy = float(result.stdout.strip())
    except ValueError:
        pytest.fail(f"sim_engine did not emit a scalar energy: {result.stdout!r}")
    assert math.isfinite(actual_energy), "sim_engine returned a non-finite energy"
    assert actual_energy <= threshold, f"Actual simulator energy {actual_energy} is not <= {threshold}"
    assert math.isclose(float(energy), actual_energy, rel_tol=1e-6, abs_tol=1e-4), (
        f"Reported energy {energy} does not match simulator energy {actual_energy}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
