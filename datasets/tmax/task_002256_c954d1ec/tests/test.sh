#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import shlex
import stat
import subprocess

import numpy as np

REPORT_PATH = "/home/user/stability_report.json"


def candidate_scripts():
    candidates = []
    skipped_dirs = {".cache", ".local", "__pycache__", ".git", ".venv", "venv"}

    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in skipped_dirs]
        for name in files:
            path = os.path.join(root, name)
            if path == REPORT_PATH or not os.path.isfile(path):
                continue

            suffix = os.path.splitext(name)[1].lower()
            executable = bool(os.stat(path).st_mode & stat.S_IXUSR)
            try:
                with open(path, "rb") as f:
                    shebang = f.readline(512).startswith(b"#!")
            except OSError:
                continue

            if suffix in {".py", ".sh", ".bash"} or executable or shebang:
                preferred = 0 if any(word in name.lower() for word in ("stability", "profile", "solver")) else 1
                candidates.append((preferred, path))

    return [path for _, path in sorted(candidates)]


def command_for(path):
    suffix = os.path.splitext(path)[1].lower()
    if suffix == ".py":
        return ["python3", path]
    if suffix in {".sh", ".bash"}:
        return ["bash", path]
    if os.access(path, os.X_OK):
        return [path]

    with open(path, "r", errors="replace") as f:
        first_line = f.readline().strip()
    assert first_line.startswith("#!"), f"Cannot execute profiling artifact {path}"
    return shlex.split(first_line[2:].strip()) + [path]


def execute_profiling_artifact():
    candidates = candidate_scripts()
    assert candidates, "No executable profiling script or program was found under /home/user."

    failures = []
    for path in candidates:
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        try:
            result = subprocess.run(
                command_for(path),
                cwd="/home/user",
                env={**os.environ, "HOME": "/home/user"},
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=90,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            failures.append(f"{path}: {exc}")
            continue

        if result.returncode == 0 and os.path.isfile(REPORT_PATH):
            return path
        failures.append(f"{path}: exit {result.returncode}, report_created={os.path.isfile(REPORT_PATH)}")

    assert False, "No profiling artifact successfully recreated the report. " + "; ".join(failures)


def independently_compute_slopes():
    np.random.seed(42)
    condition_numbers = np.array([1e2, 1e4, 1e6, 1e8], dtype=float)
    x_true = np.ones(100)
    errors_lu = []
    errors_qr = []

    for k in condition_numbers:
        x = np.random.normal(0.0, 1.0, (100, 100))
        u, _, vt = np.linalg.svd(x)
        singular_values = np.logspace(np.log10(k), 0.0, 100)
        a = (u * singular_values) @ vt
        b = a @ x_true

        x_lu = np.linalg.solve(a, b)
        q, r = np.linalg.qr(a)
        x_qr = np.linalg.solve(r, q.T @ b)

        denominator = np.linalg.norm(x_true, 2)
        errors_lu.append(np.linalg.norm(x_lu - x_true, 2) / denominator)
        errors_qr.append(np.linalg.norm(x_qr - x_true, 2) / denominator)

    log_k = np.log10(condition_numbers)
    slope_lu = float(np.polyfit(log_k, np.log10(errors_lu), 1)[0])
    slope_qr = float(np.polyfit(log_k, np.log10(errors_qr), 1)[0])
    return slope_lu, slope_qr


def test_stability_report():
    executed_path = execute_profiling_artifact()
    assert os.path.isfile(executed_path), "The profiling artifact disappeared after execution."

    report_path = "/home/user/stability_report.json"
    assert os.path.isfile(report_path), f"File {report_path} does not exist."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {report_path} is not valid JSON."

    assert "slope_lu" in data, "Key 'slope_lu' missing from JSON."
    assert "slope_qr" in data, "Key 'slope_qr' missing from JSON."

    slope_lu = data["slope_lu"]
    slope_qr = data["slope_qr"]

    assert isinstance(slope_lu, (int, float)), "slope_lu must be a number."
    assert isinstance(slope_qr, (int, float)), "slope_qr must be a number."

    expected_lu = 0.9996
    expected_qr = 1.0028

    # Preserve the original 5% acceptance checks.
    assert math.isclose(slope_lu, expected_lu, rel_tol=0.05), f"slope_lu {slope_lu} is not within 5% of {expected_lu}"
    assert math.isclose(slope_qr, expected_qr, rel_tol=0.05), f"slope_qr {slope_qr} is not within 5% of {expected_qr}"

    derived_lu, derived_qr = independently_compute_slopes()
    assert math.isclose(slope_lu, derived_lu, rel_tol=0.05), f"slope_lu {slope_lu} disagrees with independently computed slope {derived_lu}"
    assert math.isclose(slope_qr, derived_qr, rel_tol=0.05), f"slope_qr {slope_qr} disagrees with independently computed slope {derived_qr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
