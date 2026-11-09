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
from collections import Counter

import pytest

DB_PATH = "/home/user/comms.db"
FLAGGED_USER_PATH = "/home/user/flagged_user.txt"
ANALYZER_GO_PATH = "/home/user/analyzer.go"
BUILD_PATH = "/tmp/analyzer_submission"


@pytest.fixture(scope="module", autouse=True)
def restore_agent_files(tmp_path_factory):
    backup_dir = tmp_path_factory.mktemp("backup")
    db_backup = backup_dir / "comms.db"
    shutil.copy2(DB_PATH, db_backup)

    output_existed = os.path.exists(FLAGGED_USER_PATH)
    output_content = None
    if output_existed:
        with open(FLAGGED_USER_PATH, "rb") as f:
            output_content = f.read()

    yield

    shutil.copy2(db_backup, DB_PATH)
    if output_existed:
        with open(FLAGGED_USER_PATH, "wb") as f:
            f.write(output_content)
    elif os.path.exists(FLAGGED_USER_PATH):
        os.remove(FLAGGED_USER_PATH)


def test_flagged_user_output():
    """Preserve the original exact-output assertion."""
    assert os.path.exists(FLAGGED_USER_PATH), f"Output file not found at {FLAGGED_USER_PATH}"
    with open(FLAGGED_USER_PATH, "r") as f:
        content = f.read().strip()
    assert content == "42", f"Expected flagged_user.txt to contain '42', but got '{content}'"


def test_index_created():
    """Preserve the original index assertions."""
    assert os.path.exists(DB_PATH), f"Database file missing: {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_dept_time';")
    index = cursor.fetchone()
    assert index is not None, "Index 'idx_dept_time' was not found in the database."

    cursor.execute("PRAGMA index_info('idx_dept_time');")
    columns = cursor.fetchall()
    assert len(columns) >= 2, "Index 'idx_dept_time' does not have enough columns."
    col_names = [col[2] for col in sorted(columns, key=lambda x: x[0])]
    assert col_names[0] == "department", f"Expected first column in index to be 'department', got '{col_names[0]}'"
    assert col_names[1] == "timestamp", f"Expected second column in index to be 'timestamp', got '{col_names[1]}'"
    conn.close()


def test_go_script_exists_and_has_required_implementation():
    """Check the requested driver, parameterized SQL, and in-memory graph representation."""
    assert os.path.exists(ANALYZER_GO_PATH), f"Go script not found at {ANALYZER_GO_PATH}"
    assert os.path.isfile(ANALYZER_GO_PATH), f"Path {ANALYZER_GO_PATH} is not a file"

    with open(ANALYZER_GO_PATH, "r", encoding="utf-8") as f:
        source = f.read()

    assert "github.com/mattn/go-sqlite3" in source, "analyzer.go must import github.com/mattn/go-sqlite3"

    # Remove comments before inspecting implementation tokens.
    clean = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    clean = re.sub(r"//[^\n]*", "", clean)
    lower = clean.lower()

    assert re.search(r"\.(query|querycontext|prepare|preparecontext)\s*\(", clean, re.I), \
        "analyzer.go must query SQLite for the filtered rows"
    assert "select" in lower and "messages" in lower and "department" in lower and "timestamp" in lower, \
        "analyzer.go must select the required message fields and filters"

    # The two filter values must be represented by SQL bind placeholders, not embedded in SQL.
    string_values = []
    for match in re.finditer(r'`([^`]*)`|"((?:\\.|[^"\\])*)"', clean, flags=re.S):
        value = match.group(1) if match.group(1) is not None else match.group(2)
        string_values.append(value)
    sql_parts = [s for s in string_values if re.search(r"select|messages|where|department|timestamp|[?$:@]", s, re.I)]
    sql_text = " ".join(sql_parts)
    placeholders = re.findall(r"\?|\$[A-Za-z_0-9]+|:[A-Za-z_][A-Za-z_0-9]*|@[A-Za-z_][A-Za-z_0-9]*", sql_text)
    assert len(placeholders) >= 2, "department and timestamp must both be supplied through SQL parameters"
    assert "Trading" not in sql_text and "1672531200" not in sql_text, \
        "filter values must not be embedded in the SQL query text"

    has_map = re.search(r"\bmap\s*\[", clean) is not None
    has_edge_slice = "append(" in clean and re.search(r"\[\]\s*(?:struct\b|[A-Za-z_][A-Za-z_0-9]*|int\b)", clean) is not None
    assert has_map or has_edge_slice, "analyzer.go must map rows into an in-memory graph structure"


def run_analyzer_and_read_output():
    if os.path.exists(FLAGGED_USER_PATH):
        os.remove(FLAGGED_USER_PATH)
    subprocess.run([BUILD_PATH], cwd="/home/user", check=True, timeout=20)
    assert os.path.isfile(FLAGGED_USER_PATH), "analyzer did not create flagged_user.txt"
    with open(FLAGGED_USER_PATH, "r") as f:
        return f.read().strip()


def test_analyzer_compiles_and_runs_on_original_database():
    subprocess.run(
        ["go", "build", "-o", BUILD_PATH, ANALYZER_GO_PATH],
        cwd="/home/user",
        check=True,
        timeout=120,
    )
    assert run_analyzer_and_read_output() == "42", \
        "compiled analyzer produced the wrong result for the original database"


def install_messages(rows):
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("DELETE FROM messages")
        conn.executemany(
            "INSERT INTO messages (msg_id, sender_id, receiver_id, timestamp, department) VALUES (?, ?, ?, ?, ?)",
            rows,
        )
        conn.commit()
    finally:
        conn.close()


def expected_sender_from_database():
    conn = sqlite3.connect(DB_PATH)
    try:
        senders = [row[0] for row in conn.execute(
            "SELECT sender_id FROM messages WHERE department = ? AND timestamp >= ?",
            ("Trading", 1672531200),
        )]
    finally:
        conn.close()
    assert senders, "verifier generated an empty filtered dataset"
    counts = Counter(senders)
    highest = max(counts.values())
    return min(sender for sender, count in counts.items() if count == highest)


def test_analyzer_on_derived_hidden_datasets():
    rng = secrets.SystemRandom()
    ids = rng.sample(range(1000, 1000000), 10)
    a, b, c, d, e, f = ids[:6]

    datasets = []

    # Repeated messages to one receiver still count as distinct sent messages.
    rows = []
    msg = 1
    for _ in range(5):
        rows.append((msg, a, c, 1672531200 + msg, "Trading")); msg += 1
    for receiver in (c, d, e, f):
        rows.append((msg, b, receiver, 1672531300 + msg, "Trading")); msg += 1
    rows.extend([
        (msg, b, c, 1672531199, "Trading"),
        (msg + 1, b, c, 1672539999, "Sales"),
    ])
    datasets.append(rows)

    # A tie must select the numerically lowest sender ID.
    low, high = sorted((d, e))
    rows = []
    msg = 100
    for sender in (high, low):
        for receiver in rng.sample(ids, 3):
            rows.append((msg, sender, receiver, 1672531200 + rng.randrange(1, 5000), "Trading"))
            msg += 1
    rows.extend([
        (msg, f, a, 1672531190, "Trading"),
        (msg + 1, f, a, 1672535000, "Engineering"),
    ])
    datasets.append(rows)

    # A randomized distribution prevents passing with a fixed sender ID.
    rows = []
    msg = 200
    active = ids[6:10]
    for _ in range(35):
        rows.append((msg, rng.choice(active), rng.choice(ids), 1672531200 + rng.randrange(0, 100000), "Trading"))
        msg += 1
    for _ in range(12):
        rows.append((msg, rng.choice(ids), rng.choice(ids), 1672531199 - rng.randrange(0, 1000), "Trading"))
        msg += 1
        rows.append((msg, rng.choice(ids), rng.choice(ids), 1672531200 + rng.randrange(0, 1000), "Sales"))
        msg += 1
    datasets.append(rows)

    for rows in datasets:
        install_messages(rows)
        expected = str(expected_sender_from_database())
        actual = run_analyzer_and_read_output()
        assert actual == expected, f"Expected dynamically derived sender_id {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
