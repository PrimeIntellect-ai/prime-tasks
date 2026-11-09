#!/bin/bash
set -e
mkdir -p /logs/verifier

SQLITE_BIN="$(command -v sqlite3)"
REAL_SQLITE="$(mktemp /tmp/sqlite3.real.XXXXXX)"
SQL_TRACE="/tmp/sqlite3-agent-trace.log"
cp -p "$SQLITE_BIN" "$REAL_SQLITE"
: > "$SQL_TRACE"
chmod 666 "$SQL_TRACE"

cat > "$SQLITE_BIN" <<WRAPPER_EOF
#!/bin/bash
tmp=\$(mktemp /tmp/sqlite3.stdin.XXXXXX)
cat > "\$tmp"
{
    printf '\n=== sqlite3 invocation ===\n'
    printf 'ARG:%s\n' "\$@"
    cat "\$tmp"
} >> "$SQL_TRACE"
"$REAL_SQLITE" "\$@" < "\$tmp"
rc=\$?
rm -f "\$tmp"
exit \$rc
WRAPPER_EOF
chmod 755 "$SQLITE_BIN"
trap 'cp -p "$REAL_SQLITE" "$SQLITE_BIN"; rm -f "$REAL_SQLITE"' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import shutil
import sqlite3
import subprocess

SCRIPT_PATH = "/home/user/audit.sh"
DB_PATH = "/home/user/infrastructure.db"
CSV_PATH = "/home/user/suspicious_access.csv"
SQL_TRACE = "/tmp/sqlite3-agent-trace.log"
EXPECTED_HEADER = ["username", "accessed_hostname", "event_time", "access_rank"]


def get_expected_data():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    query = """
    SELECT
        u.username,
        a.hostname AS accessed_hostname,
        e.event_time,
        ROW_NUMBER() OVER (PARTITION BY u.uid, a.asset_id ORDER BY e.event_time) as access_rank
    FROM access_events e
    JOIN users u ON e.uid = u.uid
    JOIN assets a ON e.asset_id = a.asset_id
    WHERE a.asset_id IN (
        SELECT c1.from_asset
        FROM connections c1
        JOIN connections c2 ON c1.to_asset = c2.from_asset
        JOIN assets a_rest ON c2.to_asset = a_rest.asset_id
        WHERE a_rest.classification = 'Restricted'
    )
    ORDER BY u.username ASC, e.event_time ASC;
    """
    cursor.execute(query)
    rows = cursor.fetchall()
    conn.close()
    return [[str(item) for item in row] for row in rows]


def run_and_check_output():
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to execute. Stderr: {result.stderr}"
    assert os.path.isfile(CSV_PATH), f"Output file {CSV_PATH} was not created."

    with open(CSV_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        actual_rows = list(reader)

    assert header == EXPECTED_HEADER, f"CSV header is incorrect. Expected {EXPECTED_HEADER}, got {header}"
    expected_rows = get_expected_data()
    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, got {len(actual_rows)}"
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}"


def install_dynamic_fixture():
    suffix = secrets.token_hex(5)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.executescript("""
            DELETE FROM access_events;
            DELETE FROM connections;
            DELETE FROM users;
            DELETE FROM assets;
        """)
        conn.executemany("INSERT INTO users(uid, username) VALUES (?, ?)", [
            (41, f"zara_{suffix}"),
            (42, f"amy_{suffix}"),
            (43, f"ben_{suffix}"),
        ])
        conn.executemany("INSERT INTO assets(asset_id, hostname, classification) VALUES (?, ?, ?)", [
            (201, f"jump-a-{suffix}", "Public"),
            (202, f"proxy-a-{suffix}", "Internal"),
            (203, f"restricted-a-{suffix}", "Restricted"),
            (204, f"jump-b-{suffix}", "Public"),
            (205, f"proxy-b-{suffix}", "Internal"),
            (206, f"restricted-b-{suffix}", "Restricted"),
            (207, f"one-hop-{suffix}", "Public"),
            (208, f"irrelevant-a-{suffix}", "Public"),
            (209, f"irrelevant-b-{suffix}", "Internal"),
            (210, f"ordinary-target-{suffix}", "Internal"),
        ])
        conn.executemany("INSERT INTO connections(from_asset, to_asset) VALUES (?, ?)", [
            (201, 202), (202, 203),
            (204, 205), (205, 206),
            (207, 203),
            (208, 209), (209, 210),
        ])
        conn.executemany(
            "INSERT INTO access_events(event_id, uid, asset_id, event_time) VALUES (?, ?, ?, ?)",
            [
                (501, 41, 201, "2041-07-03 12:00:00"),
                (502, 42, 204, "2041-07-01 11:00:00"),
                (503, 41, 201, "2041-07-01 08:00:00"),
                (504, 42, 201, "2041-07-02 09:30:00"),
                (505, 42, 204, "2041-07-04 15:00:00"),
                (506, 43, 207, "2041-07-01 07:00:00"),
                (507, 43, 202, "2041-07-02 07:00:00"),
                (508, 41, 208, "2041-07-05 10:00:00"),
            ],
        )
        conn.commit()
    finally:
        conn.close()


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_execution_and_output():
    # Preserve and run all checks against the original setup database.
    backup = "/tmp/infrastructure.db.original"
    shutil.copy2(DB_PATH, backup)
    try:
        run_and_check_output()

        # Replace all known rows with unpredictable data and a different graph,
        # then require the same script to derive a fresh result.
        install_dynamic_fixture()
        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)
        run_and_check_output()

        # Verify that a SQL window expression was actually submitted to sqlite3
        # during execution, rather than merely appearing in an unused comment.
        with open(SQL_TRACE, "r", errors="replace") as f:
            submitted_sql = f.read()
        window_expression = re.compile(
            r"\b[a-z_][a-z0-9_]*\s*\([^;]*?\)\s*over\s*\(",
            re.IGNORECASE | re.DOTALL,
        )
        assert window_expression.search(submitted_sql), \
            "The script did not execute SQL containing a Window Function."
    finally:
        shutil.copy2(backup, DB_PATH)
        os.remove(backup)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
