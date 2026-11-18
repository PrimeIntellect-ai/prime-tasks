#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile


def test_cpp_source_exists():
    file_path = "/home/user/dedup_config.cpp"
    assert os.path.exists(file_path), f"Source file {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} should be a file."


def test_executable_exists():
    file_path = "/home/user/dedup_config"
    assert os.path.exists(file_path), f"Executable file {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} should be a file."
    assert os.access(file_path, os.X_OK), f"{file_path} should be executable."
    with open(file_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{file_path} should be a compiled executable."


def test_cleaned_configs_content():
    file_path = "/home/user/cleaned_configs.csv"
    assert os.path.exists(file_path), f"Output file {file_path} is missing."

    expected_lines = [
        "1678886400,server_port_,8080",
        "1678886401,db_hostname,db.local",
        "1678886402,feature_toggle_1,true",
        "1678886403,cache_size_mb,1024"
    ]

    with open(file_path, "r") as f:
        content = f.read().strip().splitlines()

    assert content == expected_lines, f"Content of {file_path} does not match the expected final state."


def test_pipeline_log_content():
    file_path = "/home/user/pipeline.log"
    assert os.path.exists(file_path), f"Log file {file_path} is missing."

    expected_content = "Processed: 8 lines, Duplicates dropped: 4 lines"

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"Content of {file_path} does not match the expected final state. Got: {content}"


def normalize(key):
    result = []
    for ch in key:
        if "A" <= ch <= "Z":
            result.append(chr(ord(ch) + ord("a") - ord("A")))
        elif ("a" <= ch <= "z") or ("0" <= ch <= "9"):
            result.append(ch)
        else:
            result.append("_")
    return "".join(result)


def expected_for(records):
    seen = set()
    output = []
    duplicates = 0
    for timestamp, key, value in records:
        normalized = normalize(key)
        identity = (timestamp, normalized)
        if identity in seen:
            duplicates += 1
            continue
        seen.add(identity)
        output.append(f"{timestamp},{normalized},{value}")
    return output, f"Processed: {len(records)} lines, Duplicates dropped: {duplicates} lines"


def exercise(binary, records):
    input_data = "".join(f"{timestamp},{key},{value}\n" for timestamp, key, value in records)
    expected_stdout, expected_stderr = expected_for(records)
    completed = subprocess.run(
        [binary],
        input=input_data,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=False,
    )
    assert completed.returncode == 0, f"{binary} exited with {completed.returncode}: {completed.stderr}"
    assert completed.stdout.splitlines() == expected_stdout
    assert completed.stderr.strip() == expected_stderr
    assert len(completed.stderr.strip().splitlines()) == 1


def test_source_compiles_and_program_handles_unseen_stream():
    nonce = secrets.token_hex(8)
    base_timestamp = 1800000000 + secrets.randbelow(10000000)
    records = [
        (str(base_timestamp), f"Alpha-{nonce}!!Key", f"first-{nonce}"),
        (str(base_timestamp), f"ALPHA-{nonce}@@KEY", "not-a-duplicate-because-punctuation-differs"),
        (str(base_timestamp + 1), "Mixed Case / Key.9", "value-one"),
        (str(base_timestamp + 1), "MIXED CASE / KEY.9", "duplicate-value"),
        (str(base_timestamp + 2), "A!!B", "adjacent-punctuation"),
        (str(base_timestamp + 2), "a@@b", "duplicate-after-normalization"),
        (str(base_timestamp + 3), "Already_clean9", "kept"),
    ]

    for i in range(10000):
        timestamp = str(base_timestamp + 100 + i)
        key = f"Batch-{nonce}-Item!!{i}"
        records.append((timestamp, key, f"value-{i}-{nonce}"))
        if i % 4 == 0:
            records.append((timestamp, f"BATCH-{nonce}-ITEM!!{i}", f"retry-{i}"))

    with tempfile.TemporaryDirectory() as directory:
        rebuilt = os.path.join(directory, "dedup_config")
        compile_result = subprocess.run(
            ["g++", "-O2", "/home/user/dedup_config.cpp", "-o", rebuilt],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )
        assert compile_result.returncode == 0, f"Source failed to compile: {compile_result.stderr}"
        exercise("/home/user/dedup_config", records)
        exercise(rebuilt, records)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
