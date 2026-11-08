#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import io
import os
import sqlite3
import subprocess
import tokenize

WORKER1_EXPECTED = b'''import sqlite3
import time

conn = sqlite3.connect('/home/user/audit.db', timeout=10)
try:
    conn.execute('BEGIN')
    conn.execute('SELECT * FROM accounts WHERE id=1')
    time.sleep(2)
    conn.execute('UPDATE accounts SET status="auditing" WHERE id=1')
    conn.commit()
except Exception as e:
    print("Worker 1 failed:", e)
finally:
    conn.close()
'''

WORKER2_ORIGINAL = '''import sqlite3
import time

conn = sqlite3.connect('/home/user/audit.db', timeout=10)
try:
    conn.execute('BEGIN')
    conn.execute('SELECT * FROM accounts WHERE id=2')
    time.sleep(2)
    conn.execute('UPDATE accounts SET status="auditing" WHERE id=2')
    conn.commit()
except Exception as e:
    print("Worker 2 failed:", e)
finally:
    conn.close()
'''


def token_signature(source):
    signature = []
    ignored = {
        tokenize.ENCODING,
        tokenize.COMMENT,
        tokenize.NL,
        tokenize.ENDMARKER,
    }
    for token in tokenize.tokenize(io.BytesIO(source.encode('utf-8')).readline):
        if token.type in ignored:
            continue
        value = token.string
        if token.type == tokenize.STRING:
            value = ast.literal_eval(value)
        signature.append((token.type, value))
    return signature


def test_flagged_accounts():
    flagged_file = "/home/user/flagged_accounts.txt"
    assert os.path.isfile(flagged_file), f"File {flagged_file} does not exist."

    with open(flagged_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected = [
        "http://example.org/account/Acc1",
        "http://example.org/account/Acc10",
        "http://example.org/account/Acc2",
        "http://example.org/account/Acc3",
        "http://example.org/account/Acc8",
        "http://example.org/account/Acc9"
    ]

    assert lines == expected, f"Contents of {flagged_file} do not match the expected list of URIs or are not sorted correctly."


def test_worker1_unmodified():
    worker1 = "/home/user/worker1.py"
    assert os.path.isfile(worker1), f"{worker1} is missing."
    with open(worker1, "rb") as f:
        content = f.read()
    assert content == WORKER1_EXPECTED, "worker1.py was modified, contrary to the task constraint."


def test_worker2_modified():
    worker2 = "/home/user/worker2.py"
    assert os.path.isfile(worker2), f"{worker2} is missing."
    with open(worker2, "r", encoding="utf-8") as f:
        content = f.read()

    upper_content = content.upper()
    assert "BEGIN IMMEDIATE" in upper_content or "BEGIN EXCLUSIVE" in upper_content, (
        "worker2.py does not appear to use BEGIN IMMEDIATE or BEGIN EXCLUSIVE to prevent deadlocks."
    )

    original_tokens = token_signature(WORKER2_ORIGINAL)
    submitted_tokens = token_signature(content)
    assert len(submitted_tokens) == len(original_tokens), (
        "worker2.py must retain the original SELECT-then-UPDATE logic and only change how the transaction begins."
    )

    differences = [
        (index, expected, actual)
        for index, (expected, actual) in enumerate(zip(original_tokens, submitted_tokens))
        if expected != actual
    ]
    assert len(differences) == 1, (
        "worker2.py must retain the original SELECT-then-UPDATE logic and only change how the transaction begins."
    )
    _, expected, actual = differences[0]
    assert expected == (tokenize.STRING, "BEGIN"), (
        "The only permitted logical change in worker2.py is to the BEGIN statement."
    )
    assert actual in {
        (tokenize.STRING, "BEGIN IMMEDIATE"),
        (tokenize.STRING, "BEGIN EXCLUSIVE"),
    }, "worker2.py must initiate the transaction with BEGIN IMMEDIATE or BEGIN EXCLUSIVE."


def test_deadlock_resolution():
    db_path = "/home/user/audit.db"
    assert os.path.isfile(db_path), f"Database {db_path} does not exist."

    # Reset the database to ensure a clean test
    conn = sqlite3.connect(db_path)
    conn.execute("UPDATE accounts SET status='pending'")
    conn.commit()
    conn.close()

    worker1 = "/home/user/worker1.py"
    worker2 = "/home/user/worker2.py"

    assert os.path.isfile(worker1), f"{worker1} is missing."
    assert os.path.isfile(worker2), f"{worker2} is missing."

    # Run both scripts concurrently
    p1 = subprocess.Popen(["python3", worker1], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    p2 = subprocess.Popen(["python3", worker2], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        out1, err1 = p1.communicate(timeout=20)
        out2, err2 = p2.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        p1.kill()
        p2.kill()
        p1.communicate()
        p2.communicate()
        raise AssertionError("Concurrent workers did not finish within the timeout.")

    assert p1.returncode == 0, f"worker1.py exited unsuccessfully: {(out1 + err1).decode(errors='replace')}"
    assert p2.returncode == 0, f"worker2.py exited unsuccessfully: {(out2 + err2).decode(errors='replace')}"

    # Check if both accounts were updated to 'auditing'
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT id, status FROM accounts ORDER BY id")
    rows = cursor.fetchall()
    conn.close()

    expected_rows = [(1, 'auditing'), (2, 'auditing')]
    assert rows == expected_rows, "Deadlock occurred or scripts failed to update both accounts to 'auditing' when run concurrently."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
