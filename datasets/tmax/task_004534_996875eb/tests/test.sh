#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import subprocess
import pytest

PAYLOAD_PATH = "/home/user/payload.bin"
WAL_PATH = "/home/user/corrupted.wal"
DB_PATH = "/home/user/recovered.db"
FLAG_PATH = "/home/user/flag.txt"
PROJECT_PATH = "/home/user/db_recovery"
PARSER_PATH = "/home/user/db_recovery/src/parser.rs"
EXPECTED_PAYLOAD = bytes.fromhex("ff1c161b1d05080f090e051d1e1805081f19150c1f0803056363686b")
EXPECTED_FLAG = "FLAG_RUST_GDB_RECOVERY_9921"


def test_payload_extracted_correctly():
    assert os.path.isfile(PAYLOAD_PATH), f"Missing file: {PAYLOAD_PATH}"
    with open(PAYLOAD_PATH, "rb") as f:
        data = f.read()
    assert data == EXPECTED_PAYLOAD, f"Payload data is incorrect. Expected {EXPECTED_PAYLOAD!r}, got {data!r}"


def test_parser_rs_fixed_and_behaves_safely():
    assert os.path.isfile(PARSER_PATH), f"Missing file: {PARSER_PATH}"
    with open(PARSER_PATH, "r") as f:
        content = f.read()

    original_buggy_line = "std::ptr::copy_nonoverlapping(data.as_ptr().add(1), out.as_mut_ptr(), len);"
    assert original_buggy_line not in content or "len > data.len()" in content or "min" in content, \
        "The parser.rs file does not appear to be fixed. The original unsafe bug is still present without bounds checks."

    harness = r'''
#[path = "/home/user/db_recovery/src/parser.rs"]
mod parser;

fn main() {
    assert_eq!(parser::parse_packet(&[]), Vec::<u8>::new());
    assert_eq!(parser::parse_packet(&[3, 1, 2, 3]), vec![1, 2, 3]);
    assert_eq!(parser::parse_packet(&[1, 9, 8]), vec![9]);

    let malformed = parser::parse_packet(&[255, 1, 2, 3]);
    assert!(malformed.is_empty() || malformed == vec![1, 2, 3]);

    let short = parser::parse_packet(&[8, 10, 11]);
    assert!(short.is_empty() || short == vec![10, 11]);
}
'''
    with open("/tmp/parser_harness.rs", "w") as f:
        f.write(harness)
    subprocess.run(
        ["rustc", "/tmp/parser_harness.rs", "-o", "/tmp/parser_harness"],
        check=True,
        timeout=60,
    )
    subprocess.run(["/tmp/parser_harness"], check=True, timeout=10)


def test_tool_runs_and_recovers_database():
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    result = subprocess.run(
        ["cargo", "run", "--quiet", "--", PAYLOAD_PATH, WAL_PATH],
        cwd=PROJECT_PATH,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, f"Recovery tool failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert os.path.isfile(DB_PATH), f"Missing file: {DB_PATH}. The Rust tool was not run successfully."

    with open(PAYLOAD_PATH, "rb") as f:
        payload = f.read()
    with open(WAL_PATH, "rb") as f:
        wal = f.read()
    assert payload and wal, "Recovery inputs are empty"
    derived_key = bytes(value ^ wal[0] for value in payload[1:]).decode("utf-8")
    assert derived_key == EXPECTED_FLAG

    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT recovery_key FROM secrets")
        rows = cursor.fetchall()
        conn.close()
    except sqlite3.Error as e:
        pytest.fail(f"Failed to read from recovered SQLite database: {e}")

    assert rows, "The 'secrets' table is empty or missing the expected row."
    assert rows == [(derived_key,)], f"Unexpected recovered database contents: {rows!r}"


def test_flag_extracted_correctly():
    assert os.path.isfile(FLAG_PATH), f"Missing file: {FLAG_PATH}"
    with open(FLAG_PATH, "r") as f:
        raw_flag = f.read()
    flag_content = raw_flag.strip()
    assert flag_content == EXPECTED_FLAG, f"Flag content is incorrect. Expected {EXPECTED_FLAG}, got {flag_content}"
    assert raw_flag == EXPECTED_FLAG, "flag.txt must contain only the recovery key with no extra text or whitespace"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
