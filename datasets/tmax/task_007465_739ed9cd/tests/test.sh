#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import subprocess
import sys
import tempfile

import pytest

BASE = "/home/user/mobile_build"
V1 = f"{BASE}/data/v1.db"
V2 = f"{BASE}/data/v2.db"
SIG = f"{V2}.sig"
MIGRATE = f"{BASE}/scripts/migrate.py"
TOOL_DIR = f"{BASE}/tools/db_signer"
SOURCE = f"{TOOL_DIR}/src/main.rs"
EXECUTABLE = f"{TOOL_DIR}/target/release/db_signer"

ORIGINAL_ROWS = [
    (1, 1000, 10.0),
    (2, 1005, 14.0),
    (3, 1010, 12.0),
    (4, 1015, 18.0),
    (5, 1020, 16.0),
]


def expected_rows(rows):
    result = []
    ema = None
    for row_id, ts, val in sorted(rows, key=lambda row: row[1]):
        ema = val if ema is None else val * 0.25 + ema * 0.75
        result.append((row_id, ts, val, ema))
    return result


def assert_v1_contents(path, expected):
    assert os.path.isfile(path), f"Original v1.db is missing at {path}."
    with sqlite3.connect(path) as conn:
        tables = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        ).fetchall()
        assert tables == [("raw_metrics",)], f"Unexpected v1.db tables: {tables}"
        schema = conn.execute("PRAGMA table_info(raw_metrics)").fetchall()
        assert [(r[1], r[2], r[5]) for r in schema] == [
            ("id", "INTEGER", 1),
            ("ts", "INTEGER", 0),
            ("val", "REAL", 0),
        ], f"Unexpected raw_metrics schema: {schema}"
        rows = conn.execute("SELECT id, ts, val FROM raw_metrics ORDER BY id").fetchall()
    assert rows == expected, f"v1.db was modified: expected {expected}, got {rows}"


def assert_v2_rows(expected):
    assert os.path.isfile(V2), f"Migrated v2.db is missing at {V2}."
    with sqlite3.connect(V2) as conn:
        table = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='metrics_v2'"
        ).fetchone()
        assert table is not None, "Table 'metrics_v2' does not exist in v2.db."
        schema = conn.execute("PRAGMA table_info(metrics_v2)").fetchall()
        assert [(r[1], r[2], r[5]) for r in schema] == [
            ("id", "INTEGER", 1),
            ("ts", "INTEGER", 0),
            ("val", "REAL", 0),
            ("ema", "REAL", 0),
        ], f"Unexpected metrics_v2 schema: {schema}"
        actual = conn.execute(
            "SELECT id, ts, val, ema FROM metrics_v2 ORDER BY ts ASC"
        ).fetchall()
    assert len(actual) == len(expected), f"Expected {len(expected)} rows in metrics_v2, found {len(actual)}."
    for got, wanted in zip(actual, expected):
        assert got[:3] == wanted[:3], f"Migrated row mismatch: expected {wanted}, got {got}"
        assert abs(got[3] - wanted[3]) < 1e-6, (
            f"EMA mismatch at id {got[0]}: expected {wanted[3]}, got {got[3]}"
        )


@pytest.fixture(scope="session", autouse=True)
def execute_submitted_artifacts():
    assert os.path.isfile(MIGRATE), f"Migration script missing at {MIGRATE}."
    assert os.path.isfile(SOURCE), f"Rust source missing at {SOURCE}."
    assert os.path.isfile(f"{TOOL_DIR}/Cargo.toml"), "Cargo.toml is missing."

    assert_v1_contents(V1, ORIGINAL_ROWS)
    with open(V1, "rb") as f:
        original_bytes = f.read()

    # Exercise migrate.py against non-default records at the exact paths required
    # by the instruction, then restore the original database without altering it.
    challenge_rows = [
        (41, 930, -2.5),
        (7, 120, 8.0),
        (99, 510, 3.25),
        (13, 700, 20.5),
    ]
    fd, backup = tempfile.mkstemp(prefix=".v1-verifier-backup-", dir=os.path.dirname(V1))
    os.close(fd)
    os.unlink(backup)
    os.rename(V1, backup)
    try:
        with sqlite3.connect(V1) as conn:
            conn.execute("CREATE TABLE raw_metrics(id INTEGER PRIMARY KEY, ts INTEGER, val REAL)")
            conn.executemany("INSERT INTO raw_metrics(id, ts, val) VALUES (?, ?, ?)", challenge_rows)
        if os.path.exists(V2):
            os.unlink(V2)
        if os.path.exists(SIG):
            os.unlink(SIG)
        subprocess.run([sys.executable, MIGRATE], cwd=os.path.dirname(MIGRATE), check=True, timeout=30)
        assert_v2_rows(expected_rows(challenge_rows))
    finally:
        if os.path.exists(V1):
            os.unlink(V1)
        os.rename(backup, V1)

    with open(V1, "rb") as f:
        assert f.read() == original_bytes, "v1.db was not restored byte-for-byte after migration test."

    # Generate the required final v2.db by actually running migrate.py.
    if os.path.exists(V2):
        os.unlink(V2)
    if os.path.exists(SIG):
        os.unlink(SIG)
    subprocess.run([sys.executable, MIGRATE], cwd=os.path.dirname(MIGRATE), check=True, timeout=30)
    with open(V1, "rb") as f:
        assert f.read() == original_bytes, "migrate.py modified v1.db."

    # Force Cargo to produce the release executable from the submitted source.
    subprocess.run(["cargo", "clean"], cwd=TOOL_DIR, check=True, timeout=60)
    subprocess.run(["cargo", "build", "--release"], cwd=TOOL_DIR, check=True, timeout=120)
    assert os.path.isfile(EXECUTABLE), f"Compiled Rust tool missing at {EXECUTABLE}."
    assert os.access(EXECUTABLE, os.X_OK), f"The tool at {EXECUTABLE} is not executable."

    # Exercise the compiled signer on an independently generated input.
    with tempfile.TemporaryDirectory() as td:
        sample = os.path.join(td, "sample.bin")
        payload = bytes([0, 1, 2, 127, 128, 254, 255]) + b"signer-check"
        with open(sample, "wb") as f:
            f.write(payload)
        subprocess.run([EXECUTABLE, sample], check=True, timeout=30)
        with open(sample + ".sig", "r") as f:
            lines = f.read().strip().split("\n")
        assert lines == [
            "LABEL:SIGNED_FILE_",
            f"MSG:SIGNED_FILE_{sample}",
            f"HASH:{sum(payload) % (2**32)}",
        ], f"Signer produced unexpected output: {lines}"

    # Generate the requested final signature with the rebuilt Rust executable.
    if os.path.exists(SIG):
        os.unlink(SIG)
    subprocess.run([EXECUTABLE, V2], check=True, timeout=30)
    with open(V1, "rb") as f:
        assert f.read() == original_bytes, "The build artifacts modified v1.db."


def test_v1_db_left_unchanged():
    assert_v1_contents(V1, ORIGINAL_ROWS)


def test_v2_db_exists_and_correct():
    v1_db_path = V1
    v2_db_path = V2

    assert os.path.isfile(v1_db_path), f"Original v1.db is missing at {v1_db_path}."
    assert os.path.isfile(v2_db_path), f"Migrated v2.db is missing at {v2_db_path}."

    conn1 = sqlite3.connect(v1_db_path)
    cursor1 = conn1.cursor()
    cursor1.execute("SELECT id, ts, val FROM raw_metrics ORDER BY ts ASC;")
    v1_rows = cursor1.fetchall()
    conn1.close()

    expected_v2_rows = []
    alpha = 0.25
    current_ema = None
    for row in v1_rows:
        row_id, ts, val = row
        if current_ema is None:
            current_ema = val
        else:
            current_ema = (val * alpha) + (current_ema * (1 - alpha))
        expected_v2_rows.append((row_id, ts, val, current_ema))

    conn2 = sqlite3.connect(v2_db_path)
    cursor2 = conn2.cursor()
    cursor2.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='metrics_v2';")
    assert cursor2.fetchone() is not None, "Table 'metrics_v2' does not exist in v2.db."
    cursor2.execute("SELECT id, ts, val, ema FROM metrics_v2 ORDER BY ts ASC;")
    v2_rows = cursor2.fetchall()
    conn2.close()

    assert len(v2_rows) == len(expected_v2_rows), f"Expected {len(expected_v2_rows)} rows in metrics_v2, found {len(v2_rows)}."
    for actual, expected in zip(v2_rows, expected_v2_rows):
        assert actual[0] == expected[0], f"ID mismatch: expected {expected[0]}, got {actual[0]}"
        assert actual[1] == expected[1], f"TS mismatch: expected {expected[1]}, got {actual[1]}"
        assert actual[2] == expected[2], f"VAL mismatch: expected {expected[2]}, got {actual[2]}"
        assert abs(actual[3] - expected[3]) < 1e-6, f"EMA mismatch at id {actual[0]}: expected {expected[3]}, got {actual[3]}"


def test_signature_artifact_exists_and_valid():
    v2_db_path = V2
    sig_path = SIG

    assert os.path.isfile(v2_db_path), "v2.db is missing, cannot verify signature."
    assert os.path.isfile(sig_path), f"Signature file is missing at {sig_path}."

    with open(v2_db_path, "rb") as f:
        db_content = f.read()
    expected_hash = sum(db_content) % (2**32)

    with open(sig_path, "r") as f:
        sig_content = f.read().strip().split("\n")

    assert len(sig_content) >= 3, "Signature file does not have the expected number of lines."
    label_line = sig_content[0]
    msg_line = sig_content[1]
    hash_line = sig_content[2]
    assert label_line == "LABEL:SIGNED_FILE_", f"Incorrect label line: {label_line}"
    assert msg_line == f"MSG:SIGNED_FILE_{v2_db_path}", f"Incorrect msg line: {msg_line}"
    assert hash_line == f"HASH:{expected_hash}", f"Incorrect hash line: expected HASH:{expected_hash}, got {hash_line}"


def test_rust_tool_compiled():
    tool_executable = EXECUTABLE
    assert os.path.isfile(tool_executable), f"Compiled Rust tool missing at {tool_executable}. Did you run 'cargo build --release'?"
    assert os.access(tool_executable, os.X_OK), f"The tool at {tool_executable} is not executable."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
