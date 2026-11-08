#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shutil
import subprocess
import zlib


def test_extract_go_exists():
    path = "/home/user/extract.go"
    assert os.path.isfile(path), f"Expected Go program at {path} does not exist."


def test_sensor_A_extracted():
    path = "/home/user/extracted/sensor_A.csv"
    assert os.path.isfile(path), f"Expected extracted file {path} does not exist."

    expected_content = "timestamp,value\n1000,42.5\n1001,43.1\n"
    with open(path, "r") as f:
        content = f.read()
    assert content == expected_content, f"Content of {path} does not match expected."


def test_sensor_B_extracted():
    path = "/home/user/extracted/sensor_B.csv"
    assert os.path.isfile(path), f"Expected extracted file {path} does not exist."

    expected_content = "timestamp,value\n2000,12.5\n2001,13.1\n"
    with open(path, "r") as f:
        content = f.read()
    assert content == expected_content, f"Content of {path} does not match expected."


def test_sensor_C_not_extracted():
    path = "/home/user/extracted/sensor_C.csv"
    assert not os.path.exists(path), f"File {path} should not exist because its hash is corrupted."


def test_corrupted_log():
    path = "/home/user/corrupted.log"
    assert os.path.isfile(path), f"Expected log file {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 1, f"Expected exactly 1 entry in {path}, found {len(lines)}."
    assert lines[0] == "sensor_C.csv", f"Expected 'sensor_C.csv' in {path}, got '{lines[0]}'."


def _archive_record(name, content, corrupt=False):
    compressed_hex = zlib.compress(content).hex()
    digest = hashlib.sha256(content).hexdigest()
    if corrupt:
        digest = ("0" if digest[0] != "0" else "1") + digest[1:]
    return (
        f"FILE:{name}\n"
        f"SHA256:{digest}\n"
        f"SIZE:{len(compressed_hex)}\n"
        f"{compressed_hex}\n"
    )


def test_zz_program_executes_on_fresh_archive():
    token = secrets.token_hex(12)
    valid = [
        (f"probe_{token}_alpha.csv", f"key,value\n{token},17.25\n".encode()),
        (f"probe_{token}_beta.csv", ("sample,reading\n" + token[::-1] + ",-8.75\n").encode()),
    ]
    corrupt = [
        (f"probe_{token}_bad1.csv", f"hidden,{token},101\n".encode()),
        (f"probe_{token}_bad2.csv", f"hidden,{token[::-1]},202\n".encode()),
    ]

    archive = "RSCH_ARCHIVE_V1\n"
    for name, content in valid:
        archive += _archive_record(name, content)
    for name, content in corrupt:
        archive += _archive_record(name, content, corrupt=True)

    with open("/home/user/dataset.txt", "w", encoding="ascii") as f:
        f.write(archive)

    shutil.rmtree("/home/user/extracted", ignore_errors=True)
    try:
        os.remove("/home/user/corrupted.log")
    except FileNotFoundError:
        pass

    result = subprocess.run(
        ["go", "run", "/home/user/extract.go"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"Go extractor failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    output_dir = "/home/user/extracted"
    assert os.path.isdir(output_dir), "Extractor did not create /home/user/extracted."
    expected_names = {name for name, _ in valid}
    actual_names = set(os.listdir(output_dir))
    assert actual_names == expected_names, (
        f"Unexpected extracted files: expected {expected_names}, got {actual_names}."
    )

    for name, expected_content in valid:
        path = os.path.join(output_dir, name)
        assert os.path.isfile(path), f"Expected extracted file {path} does not exist."
        with open(path, "rb") as f:
            assert f.read() == expected_content, f"Incorrect decompressed content in {path}."

    for name, _ in corrupt:
        assert not os.path.exists(os.path.join(output_dir, name)), (
            f"Corrupted file {name} must not be extracted."
        )

    log_path = "/home/user/corrupted.log"
    assert os.path.isfile(log_path), "Extractor did not create corrupted.log."
    with open(log_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines == [name for name, _ in corrupt], (
        f"Incorrect corrupted.log entries: {lines}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
