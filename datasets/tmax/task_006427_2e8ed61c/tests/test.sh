#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

DB_PATH = "/home/user/audit.db"
SCRIPT_PATH = "/home/user/find_ring.sh"
OUTPUT_PATH = "/home/user/deadlock_cycle.txt"


def get_expected_cycle():
    """Derive the expected cycle directly from the database."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    query = """
        SELECT t1.tx_id, t2.tx_id, t3.tx_id
        FROM transfers t1
        JOIN transfers t2 ON t1.receiver_id = t2.sender_id
        JOIN transfers t3 ON t2.receiver_id = t3.sender_id
        WHERE t3.receiver_id = t1.sender_id;
    """
    cursor.execute(query)
    rows = cursor.fetchall()
    conn.close()

    assert len(rows) > 0, "No cycle of length 3 found in the database."

    cycle_tx_ids = sorted(list(rows[0]))
    return ",".join(str(tx) for tx in cycle_tx_ids)


def run_script(expected, wrapper_dir, sqlite_log):
    if os.path.exists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)
    if os.path.exists(sqlite_log):
        os.unlink(sqlite_log)

    env = os.environ.copy()
    env["PATH"] = wrapper_dir + os.pathsep + env.get("PATH", "")
    result = subprocess.run(
        ["bash", "-x", SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed when executed. stderr: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), (
        f"Executing {SCRIPT_PATH} did not create {OUTPUT_PATH}."
    )

    invoked_sqlite = os.path.exists(sqlite_log) or re.search(
        r"(?m)^\++\s+.*\bsqlite3(?:\s|$)", result.stderr
    )
    assert invoked_sqlite, "The script did not invoke the sqlite3 CLI."

    with open(OUTPUT_PATH, "r") as f:
        actual = f.read().strip()
    assert actual == expected, (
        f"Executed script produced '{actual}', expected '{expected}'."
    )


@pytest.fixture(scope="session", autouse=True)
def execute_and_exercise_script():
    assert os.path.isfile(SCRIPT_PATH), f"Script file {SCRIPT_PATH} is missing."
    syntax = subprocess.run(
        ["bash", "-n", SCRIPT_PATH], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert syntax.returncode == 0, f"Invalid Bash syntax: {syntax.stderr}"

    with tempfile.TemporaryDirectory() as tmpdir:
        backup = os.path.join(tmpdir, "audit.db")
        wrapper_dir = os.path.join(tmpdir, "bin")
        sqlite_log = os.path.join(tmpdir, "sqlite-invoked")
        os.mkdir(wrapper_dir)
        wrapper = os.path.join(wrapper_dir, "sqlite3")
        with open(wrapper, "w") as f:
            f.write(
                "#!/bin/bash\n"
                f": > {sqlite_log!r}\n"
                "exec /usr/bin/sqlite3 \"$@\"\n"
            )
        os.chmod(wrapper, 0o755)
        shutil.copy2(DB_PATH, backup)

        original_expected = get_expected_cycle()
        try:
            run_script(original_expected, wrapper_dir, sqlite_log)

            conn = sqlite3.connect(DB_PATH)
            row = conn.execute("""
                SELECT t1.tx_id, t2.tx_id, t3.tx_id
                FROM transfers t1
                JOIN transfers t2 ON t1.receiver_id = t2.sender_id
                JOIN transfers t3 ON t2.receiver_id = t3.sender_id
                WHERE t3.receiver_id = t1.sender_id
                LIMIT 1
            """).fetchone()
            existing = {r[0] for r in conn.execute("SELECT tx_id FROM transfers")}
            replacement = []
            while len(replacement) < 3:
                candidate = secrets.randbelow(1_000_000_000) + 1_000_000
                if candidate not in existing and candidate not in replacement:
                    replacement.append(candidate)
            for old, new in zip(row, replacement):
                conn.execute("UPDATE transfers SET tx_id = ? WHERE tx_id = ?", (new, old))
            conn.commit()
            conn.close()

            changed_expected = get_expected_cycle()
            assert changed_expected != original_expected
            run_script(changed_expected, wrapper_dir, sqlite_log)
        finally:
            shutil.copy2(backup, DB_PATH)

        # Leave the required output in the state produced by the submitted script
        # against the original database.
        run_script(original_expected, wrapper_dir, sqlite_log)


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script file {SCRIPT_PATH} is missing."


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."


def test_output_content():
    expected_content = get_expected_cycle()

    with open(OUTPUT_PATH, "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"Content of {OUTPUT_PATH} is incorrect. Expected '{expected_content}', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
