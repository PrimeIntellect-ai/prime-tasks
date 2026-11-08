#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess

PROJECT_DIR = "/home/user/wal_parser"


def test_corrupt_offset_file():
    offset_file = "/home/user/corrupt_offset.txt"
    assert os.path.isfile(offset_file), f"The file {offset_file} does not exist."

    with open(offset_file, "r") as f:
        content = f.read().strip()

    assert content == "378", f"Expected the corrupt offset to be 378, but got '{content}'."

    journal_path = os.path.join(PROJECT_DIR, "test_data/journal.wal")
    expected_journal = (b"\x01\x04\x00\x00\x00ABCD" * 42) + b"\x02\xff\xff\x00\x001234567890"
    with open(journal_path, "rb") as f:
        journal = f.read()
    assert journal == expected_journal, "test_data/journal.wal was modified."

    offset = 0
    corrupt_offset = None
    while offset < len(journal):
        record_start = offset
        assert len(journal) - offset >= 5
        payload_len = int.from_bytes(journal[offset + 1:offset + 5], "little")
        offset += 5
        if payload_len > len(journal) - offset:
            corrupt_offset = record_start
            break
        offset += payload_len
    assert corrupt_offset == int(content)


def test_cargo_test_passes():
    assert os.path.isdir(PROJECT_DIR), f"The project directory {PROJECT_DIR} does not exist."

    result = subprocess.run(
        ["cargo", "test"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"cargo test failed with output:\n{result.stdout}\n{result.stderr}"


def test_lib_rs_modifications():
    lib_rs_path = os.path.join(PROJECT_DIR, "src/lib.rs")
    assert os.path.isfile(lib_rs_path), f"The file {lib_rs_path} does not exist."

    with open(lib_rs_path, "r") as f:
        content = f.read()

    # Preserve the original verifier's source-level assertions.
    assert "pub enum Error {" in content, "The Error enum declaration is missing or modified."
    assert "UnexpectedEof," in content, "The UnexpectedEof variant is missing."
    assert "pub fn parse_wal(data: &[u8]) -> Result<usize, Error>" in content, "The parse_wal function signature was modified."

    # The task permits changes only inside parse_wal, so the original regression
    # test must still be present. Behavioral verification below does not rely on it.
    assert "fn test_corrupt_wal()" in content, "The original corrupt-WAL test was removed."
    assert 'std::fs::read("test_data/journal.wal")' in content, "The original test no longer reads the journal."
    assert "assert_eq!(result, Err(Error::UnexpectedEof));" in content, "The original regression assertion was removed."


def reference_parse(data):
    offset = 0
    count = 0
    while offset < len(data):
        if len(data) - offset < 5:
            return None
        payload_len = int.from_bytes(data[offset + 1:offset + 5], "little")
        offset += 5
        if payload_len > len(data) - offset:
            return None
        offset += payload_len
        count += 1
    return count


def rust_vec(data):
    return "vec![" + ",".join(str(b) for b in data) + "]"


def test_parse_wal_generated_behavior():
    rng = random.SystemRandom()
    cases = [
        b"",
        b"\x01\x00\x00\x00\x00",
        b"\x01\x03\x00\x00\x00abc",
        b"\x01",
        b"\x01\x00\x00\x00",
        b"\x01\xff\xff\xff\xff",
        b"\x01\x04\x00\x00\x00abc",
        (b"\x07\x01\x00\x00\x00x" * 8),
        (b"\x07\x01\x00\x00\x00x" * 8) + b"\x09\xff\xff\xff\xfftail",
    ]

    for _ in range(180):
        data = bytearray()
        for _ in range(rng.randrange(0, 12)):
            payload = bytes(rng.randrange(256) for _ in range(rng.randrange(0, 65)))
            data.append(rng.randrange(256))
            data.extend(len(payload).to_bytes(4, "little"))
            data.extend(payload)

        mode = rng.randrange(3)
        if mode == 0:
            pass
        elif mode == 1:
            data.extend(bytes(rng.randrange(256) for _ in range(rng.randrange(1, 5))))
        else:
            available = rng.randrange(0, 24)
            declared = available + rng.randrange(1, 100000)
            data.append(rng.randrange(256))
            data.extend(declared.to_bytes(4, "little"))
            data.extend(bytes(rng.randrange(256) for _ in range(available)))
        cases.append(bytes(data))

    entries = []
    for data in cases:
        expected = reference_parse(data)
        expected_rust = "Err(Error::UnexpectedEof)" if expected is None else f"Ok({expected}usize)"
        entries.append(f"({rust_vec(data)}, {expected_rust})")

    integration_dir = os.path.join(PROJECT_DIR, "tests")
    os.makedirs(integration_dir, exist_ok=True)
    test_path = os.path.join(integration_dir, "verifier_dynamic.rs")
    source = """use wal_parser::{parse_wal, Error};

#[test]
fn verifier_generated_cases() {
    let cases: Vec<(Vec<u8>, Result<usize, Error>)> = vec![
        %s
    ];
    for (index, (data, expected)) in cases.into_iter().enumerate() {
        assert_eq!(parse_wal(&data), expected, "generated case {} failed", index);
    }
}
""" % ",\n        ".join(entries)

    with open(test_path, "w") as f:
        f.write(source)

    result = subprocess.run(
        ["cargo", "test", "--test", "verifier_dynamic"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"Generated parse_wal tests failed:\n{result.stdout}\n{result.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
