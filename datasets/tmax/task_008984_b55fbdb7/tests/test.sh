#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import resource
import signal
import sqlite3
import subprocess
import tempfile
import time
import pytest

MAGIC = b"SQLite format 3\x00"


def test_recovered_database():
    db_path = "/home/user/recovered.db"
    source_path = "/home/user/data/sensor.db"
    assert os.path.isfile(db_path), f"Phase 1 Failed: File {db_path} does not exist."

    try:
        result = subprocess.run(
            ["sqlite3", db_path, "PRAGMA integrity_check;"],
            capture_output=True,
            text=True,
            check=True
        )
        output = result.stdout.strip().lower()
        assert output == "ok", f"Phase 1 Failed: Integrity check returned '{output}' instead of 'ok'."
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Phase 1 Failed: sqlite3 command failed with error: {e.stderr}")
    except FileNotFoundError:
        pytest.fail("Phase 1 Failed: sqlite3 is not installed or not in PATH.")

    assert os.path.isfile(source_path), "Phase 1 Failed: Original sensor.db is missing."
    with open(source_path, "rb") as f:
        source_data = f.read()
    with open(db_path, "rb") as f:
        recovered_data = f.read()
    assert len(source_data) >= 16, "Phase 1 Failed: Original sensor.db is truncated."
    expected_repair = MAGIC + source_data[16:]
    assert recovered_data == expected_repair, (
        "Phase 1 Failed: recovered.db is not the repaired copy of sensor.db."
    )

    expected_rows = [
        (1, "S1", 10.0), (2, "S1", 20.0), (3, "S1", 30.0),
        (4, "S1", 40.0), (5, "S1", 50.0), (6, "S1", 60.0),
        (7, "S2", 100.0), (8, "S2", 100.0),
        (9, "S3", 40.0), (10, "S3", 40.0), (11, "S3", 40.0),
        (12, "S3", 40.0), (13, "S3", 40.0), (14, "S3", 40.0),
        (15, "S4", 50.0), (16, "S4", 50.0), (17, "S4", 50.0),
        (18, "S4", 50.0), (19, "S4", 50.0), (20, "S4", 50.0),
        (21, "S5", 10.0), (22, "S5", 10.0), (23, "S5", 10.0),
        (24, "S5", 10.0), (25, "S5", 10.0), (26, "S5", 10.0),
    ]
    with sqlite3.connect(db_path) as conn:
        tables = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        ).fetchall()
        assert tables == [("metrics",)], "Phase 1 Failed: recovered schema does not match sensor.db."
        columns = conn.execute("PRAGMA table_info(metrics)").fetchall()
        assert [(c[1], c[2], c[5]) for c in columns] == [
            ("id", "INTEGER", 1), ("sensor_id", "TEXT", 0), ("value", "REAL", 0)
        ], "Phase 1 Failed: metrics table schema is incorrect."
        rows = conn.execute("SELECT id, sensor_id, value FROM metrics ORDER BY id").fetchall()
        assert rows == expected_rows, "Phase 1 Failed: recovered metrics data is incomplete or incorrect."


def test_query_result():
    csv_path = "/home/user/query_result.csv"
    db_path = "/home/user/recovered.db"
    assert os.path.isfile(csv_path), f"Phase 2 Failed: File {csv_path} does not exist."

    with open(csv_path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "S4,50.0",
        "S3,40.0",
        "S1,35.0"
    ]
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"Phase 2 Failed: CSV content mismatch.\n"
        f"Expected: {expected_lines}\n"
        f"Got: {actual_lines}"
    )

    with sqlite3.connect(db_path) as conn:
        derived_rows = conn.execute(
            "SELECT sensor_id, AVG(value) AS average_value "
            "FROM metrics GROUP BY sensor_id HAVING COUNT(*) > 5 "
            "ORDER BY average_value DESC LIMIT 3"
        ).fetchall()
    derived_lines = [f"{sensor_id},{float(average)}" for sensor_id, average in derived_rows]
    assert actual_lines == derived_lines, (
        "Phase 2 Failed: query_result.csv was not produced from the required aggregation "
        f"against recovered.db. Expected {derived_lines}, got {actual_lines}."
    )
    assert content == "\n".join(derived_lines), (
        "Phase 2 Failed: output must be strict CSV with no header, blank lines, or extra whitespace."
    )


def _limit_mre():
    resource.setrlimit(resource.RLIMIT_AS, (128 * 1024 * 1024, 128 * 1024 * 1024))
    resource.setrlimit(resource.RLIMIT_CPU, (3, 3))


def test_mre_script():
    mre_path = "/home/user/mre.sh"
    assert os.path.isfile(mre_path), f"Phase 3 Failed: File {mre_path} does not exist."

    with open(mre_path, "r") as f:
        lines = f.readlines()

    assert len(lines) <= 15, f"Phase 3 Failed: MRE script is too long ({len(lines)} lines). Must be under 15 lines."

    content = "".join(lines)

    # Check for array initialization
    has_array_init = re.search(r"(declare\s+-a\s+\w+|^\s*\w+=\(\))", content, re.MULTILINE)
    assert has_array_init, "Phase 3 Failed: MRE script does not contain an array initialization (e.g., `declare -a ARR` or `ARR=()`)."

    # Check for loop
    has_loop = re.search(r"\b(while|for)\b", content)
    assert has_loop, "Phase 3 Failed: MRE script does not contain a loop (`while` or `for`)."

    # Check for array append
    has_append = re.search(r"\w+\+=\(", content)
    assert has_append, "Phase 3 Failed: MRE script does not contain an array append operation (e.g., `ARR+=()`)."

    assert os.access(mre_path, os.X_OK), "Phase 3 Failed: mre.sh is not executable."
    syntax = subprocess.run(["bash", "-n", mre_path], capture_output=True, text=True)
    assert syntax.returncode == 0, f"Phase 3 Failed: mre.sh has invalid bash syntax: {syntax.stderr}"

    initialized = set(re.findall(r"(?:declare\s+-a\s+|^\s*)([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\(\s*\)", content, re.MULTILINE))
    initialized.update(re.findall(r"declare\s+-a\s+([A-Za-z_][A-Za-z0-9_]*)", content))
    appended = re.findall(r"([A-Za-z_][A-Za-z0-9_]*)\s*\+=\s*\(", content)
    leaking_vars = initialized.intersection(appended)
    assert leaking_vars, "Phase 3 Failed: the loop must append to the same array that the script initializes."

    unbounded_loop = re.search(
        r"while\s+(?:true|:|read\b[^;\n]*)(?:\s*;|\s*\n)\s*do|for\s*\(\(\s*;\s*;\s*\)\)",
        content,
        re.MULTILINE
    )
    assert unbounded_loop, "Phase 3 Failed: MRE does not contain a continuing/unbounded input loop."
    assert content.find("+=", unbounded_loop.start()) != -1, (
        "Phase 3 Failed: array growth is not inside or after the continuing loop."
    )
    for var in leaking_vars:
        append_pos = content.find("+=", unbounded_loop.start())
        tail = content[append_pos + 2:]
        assert not re.search(rf"\b{re.escape(var)}\s*=\s*\(\s*\)|\bunset\s+{re.escape(var)}\b", tail), (
            "Phase 3 Failed: the growing array is cleared, so the demonstrated leak pattern is absent."
        )

    wrapper = r'''set -T
__verify_count=0
__verify_trace() {
    case "$BASH_COMMAND" in
        *"+=("*")"*)
            __verify_count=$((__verify_count + 1))
            if (( __verify_count <= 20 )); then printf 'x\n' >> "$TRACE_FILE"; fi
            ;;
    esac
}
trap __verify_trace DEBUG
source "$1"
'''
    trace_file = tempfile.NamedTemporaryFile(delete=False)
    trace_file.close()
    env = os.environ.copy()
    env["TRACE_FILE"] = trace_file.name
    proc = subprocess.Popen(
        ["bash", "-c", wrapper, "mre-verifier", mre_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=env,
        start_new_session=True,
        preexec_fn=_limit_mre
    )
    alive_at_half_second = False
    try:
        deadline = time.time() + 2.0
        while time.time() < deadline:
            if time.time() > deadline - 1.5 and proc.poll() is None:
                alive_at_half_second = True
            with open(trace_file.name, "r") as f:
                count = sum(1 for _ in f)
            if count >= 20:
                break
            if proc.poll() is not None:
                break
            time.sleep(0.05)
        with open(trace_file.name, "r") as f:
            count = sum(1 for _ in f)
        assert count >= 3, (
            "Phase 3 Failed: executing mre.sh did not repeatedly append to an array."
        )
        assert alive_at_half_second or count >= 20, (
            "Phase 3 Failed: mre.sh terminates instead of reproducing continuing array growth."
        )
    finally:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            pass
        os.unlink(trace_file.name)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
