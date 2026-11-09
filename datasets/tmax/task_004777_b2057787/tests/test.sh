#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import struct
import subprocess

import pytest

PROJECT_DIR = "/home/user/ticket-db"
MAIN_RS = os.path.join(PROJECT_DIR, "src/main.rs")


def test_recovered_tickets_jsonl():
    output_path = "/home/user/recovered_tickets.jsonl"
    assert os.path.isfile(output_path), f"{output_path} does not exist. Did you run the export command?"

    with open(output_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 valid JSON lines in {output_path}, but found {len(lines)}"

    expected_records = [
        {"id": 1, "desc": "Login issue"},
        {"id": 2, "desc": "Mouse broken"},
        {"id": 3, "desc": "Server down"}
    ]

    for i, line in enumerate(lines):
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} in {output_path} is not valid JSON: {line}")

        assert record == expected_records[i], f"Record {i+1} mismatch. Expected {expected_records[i]}, got {record}"


def test_cargo_test_passes_and_includes_regression_test():
    assert os.path.isdir(PROJECT_DIR), f"{PROJECT_DIR} does not exist"

    try:
        result = subprocess.run(
            ["cargo", "test"],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            check=True,
            timeout=120
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"`cargo test` failed with exit code {e.returncode}. Output:\n{e.stdout}\n{e.stderr}")

    output = result.stdout + result.stderr
    assert "test_corrupted_wal_recovery" in output, "The test output does not mention `test_corrupted_wal_recovery`. Did you add the required test?"


def test_main_rs_modified():
    assert os.path.isfile(MAIN_RS), f"{MAIN_RS} does not exist"

    with open(MAIN_RS, "r") as f:
        content = f.read()

    assert "test_corrupted_wal_recovery" in content, "The required test `test_corrupted_wal_recovery` is missing from main.rs"


def test_parse_wal_handles_unpredictable_truncation():
    assert os.path.isfile(MAIN_RS), f"{MAIN_RS} does not exist"

    nonce = secrets.token_hex(12)
    module_name = "verifier_dynamic_" + nonce
    function_name = "checks_truncated_wal_" + nonce
    records = [
        json.dumps({"nonce": nonce, "seq": 1}, separators=(",", ":")).encode(),
        json.dumps({"nonce": nonce[::-1], "seq": 2}, separators=(",", ":")).encode(),
    ]

    def rust_bytes(value):
        return ",".join(str(b) for b in value)

    partial_header = secrets.token_bytes(3)
    oversized_tail = struct.pack("<I", 1000 + secrets.randbelow(100000)) + secrets.token_bytes(3)

    injected = f'''\n
#[cfg(test)]
mod {module_name} {{
    use super::parse_wal;

    fn make_wal(records: &[&[u8]], tail: &[u8]) -> Vec<u8> {{
        let mut data = b"TKDB".to_vec();
        for record in records {{
            data.extend_from_slice(&(record.len() as u32).to_le_bytes());
            data.extend_from_slice(record);
        }}
        data.extend_from_slice(tail);
        data
    }}

    #[test]
    fn {function_name}() {{
        let first: &[u8] = &[{rust_bytes(records[0])}];
        let second: &[u8] = &[{rust_bytes(records[1])}];
        let expected = vec![
            String::from_utf8(first.to_vec()).unwrap(),
            String::from_utf8(second.to_vec()).unwrap(),
        ];

        let valid = make_wal(&[first, second], &[]);
        assert_eq!(parse_wal(&valid), expected.clone());

        let partial_length = make_wal(&[first, second], &[{rust_bytes(partial_header)}]);
        assert_eq!(parse_wal(&partial_length), expected.clone());

        let truncated_record = make_wal(&[first, second], &[{rust_bytes(oversized_tail)}]);
        assert_eq!(parse_wal(&truncated_record), expected);
    }}
}}
'''.encode()

    original = open(MAIN_RS, "rb").read()
    try:
        with open(MAIN_RS, "wb") as f:
            f.write(original)
            f.write(injected)

        result = subprocess.run(
            ["cargo", "test", function_name, "--", "--exact"],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            timeout=120
        )
        output = result.stdout + result.stderr
        assert result.returncode == 0, f"Dynamically generated corrupted-WAL test failed:\n{output}"
        assert function_name in output, f"The dynamically generated parser test did not run:\n{output}"
        assert "1 passed" in output, f"Expected exactly one generated parser test to pass:\n{output}"
    finally:
        with open(MAIN_RS, "wb") as f:
            f.write(original)


def test_application_export_matches_wal_valid_prefix():
    wal_path = os.path.join(PROJECT_DIR, "data/wal.dat")
    assert os.path.isfile(wal_path), f"{wal_path} does not exist"

    data = open(wal_path, "rb").read()
    assert data.startswith(b"TKDB"), "WAL is missing its TKDB magic bytes"

    expected = []
    cursor = 4
    while cursor < len(data):
        if len(data) - cursor < 4:
            break
        length = struct.unpack_from("<I", data, cursor)[0]
        cursor += 4
        if length > len(data) - cursor:
            break
        expected.append(data[cursor:cursor + length].decode("utf-8"))
        cursor += length

    result = subprocess.run(
        ["cargo", "run", "--quiet", "--", "export"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=120
    )
    assert result.returncode == 0, f"`cargo run -- export` failed:\n{result.stdout}\n{result.stderr}"
    assert result.stdout.splitlines() == expected, (
        "The running application did not export the valid WAL prefix. "
        f"Expected {expected!r}, got {result.stdout.splitlines()!r}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
