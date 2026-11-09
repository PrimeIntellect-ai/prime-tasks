#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile

REPORT_PATH = "/home/user/debugging_report.txt"
REPO_PATH = "/home/user/uptime_monitor"
DB_PATH = "/home/user/logs.db"
EXPECTED_QUERY = "SELECT COUNT(*) FROM ping_results WHERE status='UP';"
REGRESSED_QUERY = "SELECT COUNT(*) FROM ping_results WHERE status='DOWN';"


def run_git(*args):
    result = subprocess.run(
        ["git", *args], cwd=REPO_PATH, capture_output=True, text=True
    )
    assert result.returncode == 0, (
        f"git {' '.join(args)} failed: {result.stderr.strip()}"
    )
    return result.stdout


def derive_regression_commit():
    commits = run_git("rev-list", "--reverse", "HEAD").splitlines()
    candidates = []
    for commit in commits:
        parent_result = subprocess.run(
            ["git", "rev-parse", f"{commit}^"],
            cwd=REPO_PATH,
            capture_output=True,
            text=True,
        )
        if parent_result.returncode != 0:
            continue
        parent = parent_result.stdout.strip()
        old_source = run_git("show", f"{parent}:monitor.c")
        new_source = run_git("show", f"{commit}:monitor.c")
        if (
            EXPECTED_QUERY in old_source
            and REGRESSED_QUERY not in old_source
            and REGRESSED_QUERY in new_source
        ):
            candidates.append(commit)

    assert len(candidates) == 1, (
        "Could not uniquely identify the commit that changed the uptime query "
        "from UP to DOWN."
    )
    assert re.fullmatch(r"[0-9a-f]{40}", candidates[0])
    return candidates[0]


def expected_output_from_database():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    try:
        up_count = conn.execute(
            "SELECT COUNT(*) FROM ping_results WHERE status='UP';"
        ).fetchone()[0]
        total_count = conn.execute(
            "SELECT COUNT(*) FROM ping_results;"
        ).fetchone()[0]
    finally:
        conn.close()
    assert total_count > 0, "The supplied database unexpectedly contains no rows."
    return f"Uptime: {(up_count * 100.0) / total_count:.2f}%"


def run_monitor(expected):
    result = subprocess.run(
        [os.path.join(REPO_PATH, "monitor")],
        cwd=REPO_PATH,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"monitor exited with {result.returncode}: {result.stderr.strip()}"
    )
    assert result.stdout == expected + "\n", (
        f"monitor output was {result.stdout!r}, expected {expected + chr(10)!r}"
    )


def test_debugging_report_exists():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} is missing."


def test_debugging_report_content():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} is missing."
    with open(REPORT_PATH, "r", encoding="utf-8") as report:
        lines = report.read().splitlines()

    assert len(lines) == 3, (
        f"Expected exactly 3 lines in {REPORT_PATH}, found {len(lines)}."
    )

    expected_commit = derive_regression_commit()
    expected_uptime = expected_output_from_database()

    assert lines[0] == expected_commit, (
        f"Line 1 incorrect. Expected commit hash {expected_commit}, got {lines[0]}."
    )
    assert lines[1] == EXPECTED_QUERY, (
        f"Line 2 incorrect. Expected '{EXPECTED_QUERY}', got '{lines[1]}'."
    )
    assert lines[2] == expected_uptime, (
        f"Line 3 incorrect. Expected '{expected_uptime}', got '{lines[2]}'."
    )


def test_repository_builds_and_monitor_is_correct():
    makefile_path = os.path.join(REPO_PATH, "Makefile")
    source_path = os.path.join(REPO_PATH, "monitor.c")
    binary_path = os.path.join(REPO_PATH, "monitor")

    assert os.path.isfile(makefile_path), "Makefile is missing."
    assert os.path.isfile(source_path), "monitor.c is missing."

    with open(makefile_path, "r", encoding="utf-8") as makefile:
        makefile_lines = makefile.read().splitlines()
    assert any(
        "-lsqlite3" in line and not line.lstrip().startswith("#")
        for line in makefile_lines
    ), "The missing -lsqlite3 linker flag was not restored in the Makefile."

    with open(source_path, "r", encoding="utf-8") as source_file:
        source = source_file.read()
    prepare_pattern = re.compile(
        r'sqlite3_prepare_v2\s*\(\s*db\s*,\s*"'
        + re.escape(EXPECTED_QUERY)
        + r'"\s*,'
    )
    assert prepare_pattern.search(source), (
        "monitor.c does not pass the corrected UP-count query to "
        "sqlite3_prepare_v2."
    )

    if os.path.lexists(binary_path):
        os.remove(binary_path)
    build = subprocess.run(
        ["make"], cwd=REPO_PATH, capture_output=True, text=True, timeout=30
    )
    assert build.returncode == 0, (
        f"make failed:\n{build.stdout}\n{build.stderr}"
    )
    assert "-lsqlite3" in build.stdout + build.stderr, (
        "The actual make link command did not include -lsqlite3."
    )
    assert os.path.isfile(binary_path), "make did not produce the monitor binary."
    assert os.access(binary_path, os.X_OK), "The monitor artifact is not executable."
    with open(binary_path, "rb") as binary:
        assert binary.read(4) == b"\x7fELF", "monitor is not a compiled ELF executable."

    run_monitor(expected_output_from_database())

    backup_fd, backup_path = tempfile.mkstemp(prefix="logs-db-backup-")
    os.close(backup_fd)
    shutil.copy2(DB_PATH, backup_path)
    try:
        cases = [
            (["UP", "UP", "UP", "DOWN"], "Uptime: 75.00%"),
            (["UP", "UP", "DOWN", "DOWN", "DOWN"], "Uptime: 40.00%"),
        ]
        for statuses, expected in cases:
            conn = sqlite3.connect(DB_PATH)
            try:
                conn.execute("DELETE FROM ping_results")
                conn.executemany(
                    "INSERT INTO ping_results(timestamp, status) VALUES (?, ?)",
                    [(index + 1, status) for index, status in enumerate(statuses)],
                )
                conn.commit()
            finally:
                conn.close()
            run_monitor(expected)
    finally:
        for suffix in ("-wal", "-shm"):
            sidecar = DB_PATH + suffix
            if os.path.exists(sidecar):
                os.remove(sidecar)
        shutil.copy2(backup_path, DB_PATH)
        os.remove(backup_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
