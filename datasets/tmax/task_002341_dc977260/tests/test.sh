#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import sqlite3
import stat
import subprocess

DB_PATH = "/home/user/syslogs.db"
SCRIPT_PATH = "/home/user/find_deadlocks.sh"
CSV_PATH = "/home/user/deadlocks.csv"


def get_expected_deadlocks(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    query = """
    SELECT 
        a1.transaction_id AS txn_1,
        a2.transaction_id AS txn_2,
        a1.resource_id AS resource_1,
        a2.resource_id AS resource_2
    FROM lock_events a1
    JOIN lock_events a2 
        ON a1.transaction_id < a2.transaction_id
    JOIN lock_events w1 
        ON w1.transaction_id = a1.transaction_id 
        AND w1.resource_id = a2.resource_id 
        AND w1.event_type = 'WAIT' 
        AND w1.event_timestamp > a1.event_timestamp
    JOIN lock_events w2 
        ON w2.transaction_id = a2.transaction_id 
        AND w2.resource_id = a1.resource_id 
        AND w2.event_type = 'WAIT' 
        AND w2.event_timestamp > a2.event_timestamp
    WHERE a1.event_type = 'ACQUIRE' 
      AND a2.event_type = 'ACQUIRE'
    ORDER BY txn_1, txn_2;
    """

    cursor.execute(query)
    results = cursor.fetchall()
    conn.close()
    return [",".join(row) for row in results]


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_01_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_02_csv_exists():
    assert os.path.isfile(CSV_PATH), f"Output CSV missing at {CSV_PATH}"


def test_03_csv_contents():
    expected_lines = get_expected_deadlocks(DB_PATH)
    actual_lines = read_nonempty_lines(CSV_PATH)
    assert actual_lines == expected_lines, (
        f"CSV contents do not match expected deadlocks.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )


def test_04_script_queries_randomized_database():
    original_db = open(DB_PATH, "rb").read()
    original_db_mode = stat.S_IMODE(os.stat(DB_PATH).st_mode)
    original_csv = open(CSV_PATH, "rb").read()
    original_csv_mode = stat.S_IMODE(os.stat(CSV_PATH).st_mode)

    token = secrets.token_hex(6).upper()
    expected = []
    events = []
    timestamp = 100

    # Generate deadlocks unknown when the agent created the script.
    for index in range(3):
        txns = sorted([
            f"Q{token}_{index}_ALPHA",
            f"Q{token}_{index}_OMEGA",
        ])
        txn_1, txn_2 = txns
        resource_1 = f"OBJ_{token}_{index}_LEFT"
        resource_2 = f"OBJ_{token}_{index}_RIGHT"
        events.extend([
            (txn_1, resource_1, "ACQUIRE", timestamp),
            (txn_2, resource_2, "ACQUIRE", timestamp + 3),
            (txn_1, resource_2, "WAIT", timestamp + 7),
            (txn_2, resource_1, "WAIT", timestamp + 11),
        ])
        expected.append(f"{txn_1},{txn_2},{resource_1},{resource_2}")
        timestamp += 30

    # Add sequential and one-sided contention that must not be reported.
    events.extend([
        (f"SEQ_{token}_A", f"SEQRES_{token}", "ACQUIRE", timestamp),
        (f"SEQ_{token}_A", f"SEQRES_{token}", "RELEASE", timestamp + 1),
        (f"SEQ_{token}_B", f"SEQRES_{token}", "ACQUIRE", timestamp + 2),
        (f"PART_{token}_A", f"PARTRES_{token}_1", "ACQUIRE", timestamp + 10),
        (f"PART_{token}_B", f"PARTRES_{token}_2", "ACQUIRE", timestamp + 11),
        (f"PART_{token}_A", f"PARTRES_{token}_2", "WAIT", timestamp + 12),
    ])
    expected.sort()

    wrapper_dir = f"/tmp/sqlite-wrapper-{token}"
    log_path = os.path.join(wrapper_dir, "calls.log")
    os.mkdir(wrapper_dir)
    wrapper_path = os.path.join(wrapper_dir, "sqlite3")
    with open(wrapper_path, "w") as wrapper:
        wrapper.write("#!/bin/bash\n")
        wrapper.write(f"printf '%q ' \"$@\" >> {log_path!r}\n")
        wrapper.write(f"printf '\\n' >> {log_path!r}\n")
        wrapper.write("exec /usr/bin/sqlite3 \"$@\"\n")
    os.chmod(wrapper_path, 0o755)

    try:
        os.unlink(DB_PATH)
        conn = sqlite3.connect(DB_PATH)
        conn.execute("""
            CREATE TABLE lock_events (
                event_id INTEGER PRIMARY KEY AUTOINCREMENT,
                transaction_id TEXT,
                resource_id TEXT,
                event_type TEXT,
                event_timestamp INTEGER
            )
        """)
        conn.executemany(
            "INSERT INTO lock_events "
            "(transaction_id, resource_id, event_type, event_timestamp) "
            "VALUES (?, ?, ?, ?)",
            events,
        )
        conn.commit()
        conn.close()
        os.chmod(DB_PATH, 0o666)

        if os.path.exists(CSV_PATH):
            os.unlink(CSV_PATH)

        env = os.environ.copy()
        env["PATH"] = wrapper_dir + os.pathsep + env.get("PATH", "")
        result = subprocess.run(
            ["/bin/bash", "-x", SCRIPT_PATH],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )

        assert result.returncode == 0, (
            f"Script failed on a changed database with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(CSV_PATH), "Script did not generate deadlocks.csv when executed"

        actual = read_nonempty_lines(CSV_PATH)
        assert actual == expected, (
            "Script output is not derived correctly from a changed database.\n"
            f"Expected: {expected}\nActual: {actual}"
        )

        wrapper_called = os.path.isfile(log_path) and os.path.getsize(log_path) > 0
        traced_sqlite = re.search(
            r"(?m)^\++\s+(?:\S*/)?sqlite3(?:\s|$)", result.stderr
        ) is not None
        assert wrapper_called or traced_sqlite, (
            "The executed script produced output without invoking the sqlite3 command"
        )
    finally:
        with open(DB_PATH, "wb") as f:
            f.write(original_db)
        os.chmod(DB_PATH, original_db_mode)
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        os.chmod(CSV_PATH, original_csv_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
