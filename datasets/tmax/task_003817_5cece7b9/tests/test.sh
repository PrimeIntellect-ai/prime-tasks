#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

import h5py
import numpy as np
from scipy.optimize import curve_fit

DATA_PATH = Path("/home/user/qpcr_data.h5")
LOG_PATH = Path("/home/user/inflection.log")


def logistic(x, L, k, x0, b):
    return L / (1 + np.exp(-k * (x - x0))) + b


def test_inflection_log():
    """Verify that the inflection.log file exists and contains the correct Cq value."""
    log_path = "/home/user/inflection.log"

    assert os.path.exists(log_path), f"Required output file is missing: {log_path}"
    assert os.path.isfile(log_path), f"Path exists but is not a regular file: {log_path}"

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_value = "22.5000"
    assert content == expected_value, f"Expected {log_path} to contain exactly '{expected_value}', but got '{content}'"


def find_python_scripts():
    scripts = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for name in files:
            if not name.endswith(".py"):
                continue
            path = Path(root) / name
            try:
                if stat.S_ISREG(path.lstat().st_mode):
                    scripts.append(path)
            except OSError:
                pass
    return scripts


def write_challenge(x0):
    cycles = np.arange(1, 41, dtype=float)
    rng = np.random.default_rng(secrets.randbits(64))
    fluorescence = rng.uniform(5.0, 80.0, size=(20, 40))
    L = rng.uniform(850.0, 1250.0)
    k = rng.uniform(0.35, 0.75)
    b = rng.uniform(15.0, 65.0)
    fluorescence[15, :] = logistic(cycles, L, k, x0, b)

    with h5py.File(DATA_PATH, "w") as f:
        f.create_dataset("cycles", data=cycles)
        f.create_dataset("fluorescence", data=fluorescence)

    fitted, _ = curve_fit(
        logistic,
        cycles,
        fluorescence[15],
        p0=[np.ptp(fluorescence[15]), 0.5, 20.0, np.min(fluorescence[15])],
        bounds=([0.0, 0.001, 1.0, -np.inf], [np.inf, 5.0, 40.0, np.inf]),
        maxfev=50000,
    )
    return f"{fitted[2]:.4f}"


def test_script_reads_hdf5_and_runs_curve_fit():
    scripts = find_python_scripts()
    assert scripts, "No Python script was created under /home/user"

    original_data = DATA_PATH.read_bytes()
    original_log = LOG_PATH.read_bytes() if LOG_PATH.exists() else None
    errors = []
    successful_script = None

    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        hook_dir = td_path / "hook"
        marker_dir = td_path / "markers"
        hook_dir.mkdir()
        marker_dir.mkdir()

        (hook_dir / "sitecustomize.py").write_text(r'''
import os
import h5py
import scipy.optimize

_marker_dir = os.environ.get("VERIFIER_MARKER_DIR")
_original_file = h5py.File
_original_curve_fit = scipy.optimize.curve_fit


def tracked_file(name, *args, **kwargs):
    try:
        path = os.path.abspath(os.fspath(name))
        if _marker_dir and path == "/home/user/qpcr_data.h5":
            with open(os.path.join(_marker_dir, "h5py_called"), "a") as marker:
                marker.write(path + "\n")
    except Exception:
        pass
    return _original_file(name, *args, **kwargs)


def tracked_curve_fit(*args, **kwargs):
    if _marker_dir:
        with open(os.path.join(_marker_dir, "curve_fit_called"), "a") as marker:
            marker.write("called\n")
    return _original_curve_fit(*args, **kwargs)


h5py.File = tracked_file
scipy.optimize.curve_fit = tracked_curve_fit
''')

        try:
            for script in scripts:
                candidate_ok = True
                candidate_errors = []

                for round_number in range(2):
                    for marker in marker_dir.iterdir():
                        marker.unlink()
                    if LOG_PATH.exists() or LOG_PATH.is_symlink():
                        LOG_PATH.unlink()

                    raw_x0 = secrets.randbelow(120001) + 150000
                    x0 = raw_x0 / 10000.0
                    if abs(x0 - 22.5) < 0.01:
                        x0 += 0.1234
                    expected = write_challenge(x0)

                    env = os.environ.copy()
                    env["PYTHONPATH"] = str(hook_dir) + os.pathsep + env.get("PYTHONPATH", "")
                    env["VERIFIER_MARKER_DIR"] = str(marker_dir)

                    try:
                        result = subprocess.run(
                            ["python3", str(script)],
                            cwd="/home/user",
                            env=env,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE,
                            text=True,
                            timeout=30,
                        )
                    except Exception as exc:
                        candidate_errors.append(f"round {round_number + 1}: execution failed: {exc}")
                        candidate_ok = False
                        break

                    if result.returncode != 0:
                        candidate_errors.append(
                            f"round {round_number + 1}: exited {result.returncode}: {result.stderr[-500:]}"
                        )
                        candidate_ok = False
                        break
                    if not marker_dir.joinpath("h5py_called").exists():
                        candidate_errors.append(f"round {round_number + 1}: did not open qpcr_data.h5 through h5py")
                        candidate_ok = False
                        break
                    if not marker_dir.joinpath("curve_fit_called").exists():
                        candidate_errors.append(f"round {round_number + 1}: did not call scipy.optimize.curve_fit")
                        candidate_ok = False
                        break
                    if not LOG_PATH.exists() or not stat.S_ISREG(LOG_PATH.lstat().st_mode):
                        candidate_errors.append(f"round {round_number + 1}: did not create a regular inflection.log file")
                        candidate_ok = False
                        break

                    content = LOG_PATH.read_text().strip()
                    if not re.fullmatch(r"[+-]?\d+\.\d{4}", content):
                        candidate_errors.append(f"round {round_number + 1}: output was not one value with exactly 4 decimals: {content!r}")
                        candidate_ok = False
                        break
                    if content != expected:
                        candidate_errors.append(f"round {round_number + 1}: expected {expected}, got {content}")
                        candidate_ok = False
                        break

                if candidate_ok:
                    successful_script = script
                    break
                errors.append(f"{script}: " + "; ".join(candidate_errors))
        finally:
            DATA_PATH.write_bytes(original_data)
            if LOG_PATH.exists() or LOG_PATH.is_symlink():
                LOG_PATH.unlink()
            if original_log is not None:
                LOG_PATH.write_bytes(original_log)

    assert successful_script is not None, "No created Python script performed the required regression. " + " | ".join(errors)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
