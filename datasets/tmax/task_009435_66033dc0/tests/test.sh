#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shlex
import struct
import subprocess

SCRIPT_PATH = "/home/user/run_pipeline.sh"
SOURCE_PATH = "/home/user/process.c"
PROCESS_PATH = "/home/user/process"
CSV_PATH = "/home/user/data.csv"
BIN_PATH = "/home/user/store.bin"
VERIFIED_PROCESS = "/tmp/verified_process"


def fnv1a_64(text):
    hash_val = 14695981039346656037
    for byte in text.encode("utf-8"):
        hash_val ^= byte
        hash_val = (hash_val * 1099511628211) & 0xffffffffffffffff
    return hash_val


def expected_output(csv_bytes):
    records = []
    lines = csv_bytes.decode("utf-8").splitlines()
    for line in lines[1:]:
        if not line.strip():
            continue
        parts = line.split(",", 2)
        if len(parts) != 3:
            continue
        id_str, category, text = parts
        try:
            record_id = int(id_str)
        except ValueError:
            continue
        if record_id <= 0 or category not in ("A", "B", "C") or not text:
            continue
        records.append(struct.pack(
            "<i4sQ",
            record_id,
            category.encode("ascii").ljust(4, b"\x00"),
            fnv1a_64(text),
        ))
    return b"".join(records)


def assert_output(expected):
    assert os.path.isfile(BIN_PATH), f"Output file {BIN_PATH} does not exist."
    with open(BIN_PATH, "rb") as f:
        data = f.read()
    assert len(data) == len(expected), (
        f"File size mismatch: expected {len(expected)} bytes, got {len(data)} bytes."
    )
    assert data == expected, "Binary output records do not match the expected packed records."


def trace_has_required_commands(trace):
    compiled = False
    executed = False
    for raw_line in trace.splitlines():
        if not raw_line.startswith("+"):
            continue
        try:
            words = shlex.split(raw_line.lstrip("+ "))
        except ValueError:
            continue
        if not words:
            continue

        if os.path.basename(words[0]) == "gcc":
            has_output = False
            for i, word in enumerate(words):
                if word == "-o" and i + 1 < len(words) and words[i + 1] == PROCESS_PATH:
                    has_output = True
                if word == "-o" + PROCESS_PATH:
                    has_output = True
            if "-O3" in words and SOURCE_PATH in words and has_output:
                compiled = True

        if words[0] == PROCESS_PATH:
            executed = True
        if len(words) >= 2 and words[0] == "exec" and words[1] == PROCESS_PATH:
            executed = True

    return compiled, executed


def run_verified_process(csv_bytes):
    with open(CSV_PATH, "wb") as f:
        f.write(csv_bytes)
    if os.path.exists(BIN_PATH):
        os.remove(BIN_PATH)

    result = subprocess.run([VERIFIED_PROCESS], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Independently compiled process.c failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    with open(CSV_PATH, "rb") as f:
        assert f.read() == csv_bytes, "The C program modified the input CSV."
    assert_output(expected_output(csv_bytes))


def test_pipeline_and_output():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."
    assert os.path.isfile(SOURCE_PATH), f"C source {SOURCE_PATH} does not exist."
    assert os.path.isfile(CSV_PATH), f"Input file {CSV_PATH} does not exist."

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()
    with open(SOURCE_PATH, "rb") as f:
        original_source = f.read()
    original_expected = expected_output(original_csv)

    if os.path.exists(VERIFIED_PROCESS):
        os.remove(VERIFIED_PROCESS)
    compile_result = subprocess.run(
        ["gcc", "-O3", SOURCE_PATH, "-o", VERIFIED_PROCESS],
        capture_output=True,
        text=True,
    )
    assert compile_result.returncode == 0, (
        f"process.c failed to compile with gcc -O3.\n"
        f"Stdout: {compile_result.stdout}\nStderr: {compile_result.stderr}"
    )

    try:
        if os.path.exists(PROCESS_PATH):
            os.remove(PROCESS_PATH)
        if os.path.exists(BIN_PATH):
            os.remove(BIN_PATH)

        result = subprocess.run(["bash", "-x", SCRIPT_PATH], capture_output=True, text=True)
        assert result.returncode == 0, (
            f"Pipeline script failed with return code {result.returncode}.\n"
            f"Stdout: {result.stdout}\nStderr: {result.stderr}"
        )

        compiled, executed = trace_has_required_commands(result.stderr)
        assert compiled, (
            "Pipeline script did not run gcc -O3 on /home/user/process.c "
            "with output /home/user/process."
        )
        assert executed, "Pipeline script did not run /home/user/process."
        assert os.path.isfile(PROCESS_PATH), "Compiled executable /home/user/process does not exist."
        assert os.access(PROCESS_PATH, os.X_OK), "/home/user/process is not executable."
        with open(PROCESS_PATH, "rb") as f:
            assert f.read(4) == b"\x7fELF", "/home/user/process is not an ELF executable."

        with open(CSV_PATH, "rb") as f:
            assert f.read() == original_csv, "Pipeline modified /home/user/data.csv."
        with open(SOURCE_PATH, "rb") as f:
            assert f.read() == original_source, "Pipeline modified /home/user/process.c."
        assert_output(original_expected)

        fixtures = [
            b"id,category,text\n7,A,a\n8,B,hello\n9,C,FNV-1a test\n-2,A,bad\n10,D,bad\n11,C,\n",
            b"id,category,text\n21,C,the quick brown fox\nnot-an-id,A,reject\n22,B,1234567890\n23,A,spaces are retained\n24,C,z\n",
        ]
        for fixture in fixtures:
            run_verified_process(fixture)
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        with open(SOURCE_PATH, "wb") as f:
            f.write(original_source)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
