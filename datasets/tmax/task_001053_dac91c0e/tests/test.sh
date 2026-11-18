#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import tempfile
import time

import h5py
import numpy as np

SCRIPT = "/home/user/compute_lu.sh"
REPORT = "/home/user/report.txt"
MATRIX_FILE = "/home/user/matrix.h5"
REF_FILE = "/home/user/ref.h5"

LOOSE_TIME_RE = re.compile(r"Execution Time:\s*([0-9]*\.?[0-9]+)\s*seconds")
LOOSE_ERROR_RE = re.compile(r"Max Error:\s*([0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?)")
LOOSE_TEST_RE = re.compile(r"Test:\s*(PASS|FAIL)")
STRICT_REPORT_RE = re.compile(
    r"Execution Time: ([0-9]+\.[0-9]{2,}) seconds\n"
    r"Max Error: ([0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?)\n"
    r"Test: (PASS|FAIL)\n?\Z"
)


def validate_original_report_assertions():
    assert os.path.isfile(REPORT), f"Report file not found: {REPORT}"
    with open(REPORT, "r", encoding="utf-8") as f:
        content = f.read()

    time_match = LOOSE_TIME_RE.search(content)
    assert time_match is not None, "Report missing or invalid 'Execution Time: <time> seconds' format."

    error_match = LOOSE_ERROR_RE.search(content)
    assert error_match is not None, "Report missing or invalid 'Max Error: <error_value>' format."
    error_val = float(error_match.group(1))
    assert error_val < 1e-5, f"Max Error is not strictly less than 1e-5. Found: {error_val}"

    test_match = LOOSE_TEST_RE.search(content)
    assert test_match is not None, "Report missing or invalid 'Test: PASS' format."
    assert test_match.group(1) == "PASS", f"Expected Test: PASS, but found Test: {test_match.group(1)}"


def doolittle(a):
    n = a.shape[0]
    l = np.eye(n, dtype=float)
    u = np.zeros((n, n), dtype=float)
    for i in range(n):
        for k in range(i, n):
            u[i, k] = a[i, k] - sum(l[i, j] * u[j, k] for j in range(i))
        assert abs(u[i, i]) > 1e-12
        for k in range(i + 1, n):
            l[k, i] = (a[k, i] - sum(l[k, j] * u[j, i] for j in range(i))) / u[i, i]
    return l, u


def write_inputs(a, ref_l, ref_u):
    for path in (MATRIX_FILE, REF_FILE):
        if os.path.lexists(path):
            os.unlink(path)
    with h5py.File(MATRIX_FILE, "w") as f:
        f.create_dataset("/A", data=np.asarray(a, dtype=np.float64))
    with h5py.File(REF_FILE, "w") as f:
        f.create_dataset("/L", data=np.asarray(ref_l, dtype=np.float64))
        f.create_dataset("/U", data=np.asarray(ref_u, dtype=np.float64))
    os.chmod(MATRIX_FILE, 0o666)
    os.chmod(REF_FILE, 0o666)


def execute_and_read_report():
    if os.path.lexists(REPORT):
        os.unlink(REPORT)
    started = time.monotonic()
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "/bin/bash", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    elapsed = time.monotonic() - started
    assert os.path.isfile(REPORT), (
        "Executing compute_lu.sh did not create /home/user/report.txt. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    with open(REPORT, "r", encoding="utf-8") as f:
        content = f.read()
    match = STRICT_REPORT_RE.fullmatch(content)
    assert match is not None, f"Report does not have the exact required three-line format: {content!r}"
    reported_time = float(match.group(1))
    reported_error = float(match.group(2))
    assert np.isfinite(reported_time) and reported_time >= 0
    assert np.isfinite(reported_error) and reported_error >= 0
    assert reported_time <= elapsed + 2.0, (
        f"Reported wall time {reported_time} is inconsistent with observed runtime {elapsed:.6f}"
    )
    return result, reported_error, match.group(3)


def test_complete_lu_pipeline():
    # Preserve the original existence and report assertions.
    assert os.path.isfile(SCRIPT), f"Script not found: {SCRIPT}"
    validate_original_report_assertions()

    info = os.lstat(SCRIPT)
    assert stat.S_ISREG(info.st_mode) and not stat.S_ISLNK(info.st_mode), "compute_lu.sh must be a regular file"
    with open(SCRIPT, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert re.match(r"^#!.*\bbash\b", source), "compute_lu.sh must be a Bash script"
    syntax = subprocess.run(["/bin/bash", "-n", SCRIPT], text=True, capture_output=True)
    assert syntax.returncode == 0, f"Bash syntax check failed: {syntax.stderr}"
    assert re.search(r"\bh5dump\b", source), "compute_lu.sh must use h5dump"
    assert "matrix.h5" in source and "ref.h5" in source, "Script must read both supplied HDF5 files"
    assert re.search(r"\b(awk|gawk|SECONDS|date|time)\b", source), (
        "Script must contain the requested shell computation/profiling pipeline"
    )

    backup_dir = tempfile.mkdtemp(prefix="lu-verifier-")
    backups = {}
    try:
        for path in (MATRIX_FILE, REF_FILE, REPORT):
            if os.path.exists(path):
                backup = os.path.join(backup_dir, os.path.basename(path))
                shutil.copy2(path, backup)
                backups[path] = backup

        # Generate a fresh, non-pivoting 3x3 problem unknown to the submission.
        rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))
        l_seed = np.eye(3)
        l_seed[1, 0] = int(rng.integers(-3, 4))
        l_seed[2, 0] = int(rng.integers(-3, 4))
        l_seed[2, 1] = int(rng.integers(-3, 4))
        u_seed = np.zeros((3, 3))
        u_seed[0, 0] = int(rng.choice([-5, -4, -3, 2, 3, 4, 5]))
        u_seed[1, 1] = int(rng.choice([-5, -4, -3, 2, 3, 4, 5]))
        u_seed[2, 2] = int(rng.choice([-5, -4, -3, 2, 3, 4, 5]))
        u_seed[0, 1] = int(rng.integers(-4, 5))
        u_seed[0, 2] = int(rng.integers(-4, 5))
        u_seed[1, 2] = int(rng.integers(-4, 5))
        a = l_seed @ u_seed
        calc_l, calc_u = doolittle(a)

        write_inputs(a, calc_l, calc_u)
        result, error, outcome = execute_and_read_report()
        assert result.returncode == 0, f"Script failed on valid references: {result.stderr}"
        expected = max(np.max(np.abs(calc_l - calc_l)), np.max(np.abs(calc_u - calc_u)))
        assert abs(error - expected) <= 1e-7
        assert error < 1e-5 and outcome == "PASS", "Correct references must produce PASS"

        # A changed reference must be detected and its independently known residual reported.
        bad_l = calc_l.copy()
        bad_l[2, 1] += 0.25
        write_inputs(a, bad_l, calc_u)
        result, error, outcome = execute_and_read_report()
        expected = max(np.max(np.abs(calc_l - bad_l)), np.max(np.abs(calc_u - calc_u)))
        assert abs(error - expected) <= 1e-6, f"Expected max error {expected}, got {error}"
        assert outcome == "FAIL", "A reference error above 1e-5 must produce FAIL"
    finally:
        for path in (MATRIX_FILE, REF_FILE, REPORT):
            if os.path.lexists(path):
                os.unlink(path)
            if path in backups:
                shutil.copy2(backups[path], path)
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
