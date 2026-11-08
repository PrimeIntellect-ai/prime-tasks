#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import shutil
import sqlite3
import stat
import statistics
import subprocess
import tempfile

SCRIPT = "/home/user/anomaly_detector.py"
DB = "/home/user/telemetry.db"
THRESHOLD_FILE = "/home/user/final_threshold.txt"


def run_detector():
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert result.returncode == 0, (
        f"anomaly_detector.py failed with exit code {result.returncode}: "
        f"{result.stderr}"
    )
    output = result.stdout.strip()
    try:
        value = float(output)
    except ValueError:
        assert False, f"Script output is not exactly a float: {output!r}"
    assert math.isfinite(value), f"Script produced a non-finite threshold: {value}"
    return output, value


def expected_from_database():
    conn = sqlite3.connect(DB)
    try:
        rows = conn.execute(
            "SELECT latency FROM logs WHERE latency > 0 AND status = 'OK'"
        ).fetchall()
    finally:
        conn.close()
    values = [row[0] for row in rows]
    if not values:
        return 0.0
    return math.sqrt(statistics.pvariance(values))


def install_database(rows):
    for suffix in ("", "-wal", "-shm"):
        try:
            os.remove(DB + suffix)
        except FileNotFoundError:
            pass
    conn = sqlite3.connect(DB)
    try:
        conn.execute(
            "CREATE TABLE logs (id INTEGER PRIMARY KEY, latency REAL, status TEXT)"
        )
        conn.executemany(
            "INSERT INTO logs (latency, status) VALUES (?, ?)", rows
        )
        conn.commit()
    finally:
        conn.close()
    os.chmod(DB, 0o666)


def assert_detector_matches_database(tolerance=1.1e-7):
    expected = expected_from_database()
    _, actual = run_detector()
    assert math.isclose(actual, expected, rel_tol=0.0, abs_tol=tolerance), (
        f"Script calculated {actual}, but the independently computed threshold "
        f"for the valid database rows is {expected}"
    )


def test_final_threshold_file():
    path = THRESHOLD_FILE
    assert os.path.isfile(path), f"Expected file {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        assert False, f"Content of {path} is not a valid float: '{content}'"

    expected = 0.001707825127659933
    assert math.isclose(val, expected, abs_tol=1e-5), f"Calculated threshold {val} is not within acceptable tolerance of {expected}."


def test_anomaly_detector_fixes():
    script_path = SCRIPT
    assert os.path.isfile(script_path), f"Expected script file {script_path} does not exist."
    mode = os.stat(script_path, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), f"Expected {script_path} to be a regular file."

    with open(script_path, "r") as f:
        content = f.read()

    content_lower = content.lower()
    content_no_spaces = content.replace(" ", "")

    # Preserve the original source-level assertions.
    assert "'ok'" in content_lower or '"ok"' in content_lower, "The script must filter for status 'OK'."
    assert ">0" in content_no_spaces, "The script must filter for positive latency (> 0)."

    naive_formula = "(sum_x2-(sum_x**2)/n)/n"
    assert naive_formula not in content_no_spaces, "The naive variance formula must be removed to fix catastrophic cancellation."

    has_statistics = "statistics" in content
    has_welford = "mean" in content_lower and "m2" in content_lower
    assert has_statistics or has_welford or "variance" in content_lower, "The script should use a stable variance calculation method."

    assert "1e-7" in content_lower or "0.0000001" in content_lower, "The script must break the convergence loop when the delta is smaller than 1e-7."

    backup_dir = tempfile.mkdtemp(prefix="telemetry-verifier-")
    backup_db = os.path.join(backup_dir, "telemetry.db")
    shutil.copy2(DB, backup_db)
    threshold_existed = os.path.exists(THRESHOLD_FILE)
    threshold_backup = os.path.join(backup_dir, "final_threshold.txt")
    if threshold_existed:
        shutil.copy2(THRESHOLD_FILE, threshold_backup)

    try:
        # Execute the submitted artifact against the original database and ensure
        # the saved value is precisely the value printed by that execution.
        baseline_expected = expected_from_database()
        printed, baseline_actual = run_detector()
        assert math.isclose(
            baseline_actual, baseline_expected, rel_tol=0.0, abs_tol=1.1e-7
        ), f"Script output {baseline_actual}, expected {baseline_expected}"
        with open(THRESHOLD_FILE, "r") as f:
            saved = f.read().strip()
        assert saved == printed, (
            "final_threshold.txt must contain the precise float printed by the "
            "fixed script on telemetry.db"
        )

        # Use unpredictable high-base inputs so a fixed threshold cannot pass.
        for _ in range(3):
            base = float(100000000 + secrets.randbelow(800000000))
            offset_units = sorted({1 + secrets.randbelow(40) for _ in range(12)})
            while len(offset_units) < 6:
                offset_units.append(41 + secrets.randbelow(40))
                offset_units = sorted(set(offset_units))
            valid = [(base + unit * 0.0005, "OK") for unit in offset_units]
            invalid = [
                (None, "OK"),
                (-float(1 + secrets.randbelow(1000)), "OK"),
                (base * 50.0, "ERROR"),
                (base * 75.0, "ok"),
                (None, "ERROR"),
            ]
            install_database(valid + invalid)
            assert_detector_matches_database()

        # Exact-zero variance must terminate safely and produce zero.
        repeated = float(1000 + secrets.randbelow(100000))
        install_database([
            (repeated, "OK"),
            (repeated, "OK"),
            (repeated, "OK"),
            (None, "OK"),
            (-1.0, "OK"),
            (repeated + 9999.0, "ERROR"),
        ])
        assert_detector_matches_database()
    finally:
        for suffix in ("", "-wal", "-shm"):
            try:
                os.remove(DB + suffix)
            except FileNotFoundError:
                pass
        shutil.copy2(backup_db, DB)
        if threshold_existed:
            shutil.copy2(threshold_backup, THRESHOLD_FILE)
        else:
            try:
                os.remove(THRESHOLD_FILE)
            except FileNotFoundError:
                pass
        shutil.rmtree(backup_dir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
