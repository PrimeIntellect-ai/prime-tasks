#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import struct
import subprocess

CPP_PATH = "/home/user/extractor.cpp"
EXE_PATH = "/tmp/submission_extractor"
ARCHIVE_PATH = "/home/user/research_data.bin"
EXTRACTED_DIR = "/home/user/extracted"


def run_extractor():
    return subprocess.run(
        [EXE_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )


def test_extractor_cpp_exists():
    assert os.path.isfile(CPP_PATH), f"C++ source file {CPP_PATH} does not exist."
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", CPP_PATH, "-o", EXE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, f"Failed to compile extractor.cpp:\n{result.stderr}"


def test_extractor_executes_on_original_archive():
    shutil.rmtree(EXTRACTED_DIR, ignore_errors=True)
    result = run_extractor()
    assert result.returncode == 0, (
        f"Compiled extractor failed on research_data.bin. stderr: "
        f"{result.stderr.decode(errors='replace')}"
    )


def test_extracted_files():
    extracted_dir = "/home/user/extracted"
    assert os.path.isdir(extracted_dir), f"Directory {extracted_dir} does not exist."

    exp1_path = os.path.join(extracted_dir, "exp1.jsonl")
    exp2_path = os.path.join(extracted_dir, "exp2.jsonl")

    assert os.path.isfile(exp1_path), f"File {exp1_path} was not extracted."
    assert os.path.isfile(exp2_path), f"File {exp2_path} was not extracted."

    with open(exp1_path, "r") as f:
        exp1_content = f.read()
    assert exp1_content == '{"id": 1, "v": 150}\n{"id": 3, "v": 200}\n', f"Content of {exp1_path} is incorrect."

    with open(exp2_path, "r") as f:
        exp2_content = f.read()
    assert exp2_content == '{"id": 2, "v": 175}\n{"id": 4, "v": 220}\n', f"Content of {exp2_path} is incorrect."


def test_merged_csv():
    csv_path = "/home/user/merged.csv"
    assert os.path.isfile(csv_path), f"File {csv_path} does not exist."

    expected_csv = "id,v\n1,150\n2,175\n3,200\n4,220\n"
    expected_lines = [line.strip() for line in expected_csv.strip().split('\n')]

    with open(csv_path, "r") as f:
        actual_lines = [line.strip() for line in f.read().strip().split('\n')]

    assert actual_lines == expected_lines, f"Content of {csv_path} does not match the expected sorted CSV."


def test_extractor_handles_runtime_generated_archive():
    with open(ARCHIVE_PATH, "rb") as f:
        original_archive = f.read()

    files = []
    for index in range(3):
        name = f"d{index}{secrets.token_hex(3)}.jsonl"
        first_id = secrets.randbelow(900000) + 100000
        second_id = secrets.randbelow(900000) + 100000
        first_v = secrets.randbelow(1000000)
        second_v = secrets.randbelow(1000000)
        content = (
            f'{{"id": {first_id}, "v": {first_v}}}\n'
            f'{{"id": {second_id}, "v": {second_v}}}\n'
        ).encode("ascii")
        files.append((name, content))

    plain = bytearray(b"RDSF")
    plain += struct.pack("<I", len(files))
    for name, content in files:
        encoded_name = name.encode("ascii")
        assert len(encoded_name) <= 16
        plain += encoded_name.ljust(16, b"\x00")
        plain += struct.pack("<I", len(content))
        plain += content
    encrypted = bytes(byte ^ 0x5A for byte in plain)

    try:
        with open(ARCHIVE_PATH, "wb") as f:
            f.write(encrypted)
        shutil.rmtree(EXTRACTED_DIR, ignore_errors=True)

        result = run_extractor()
        assert result.returncode == 0, (
            f"Compiled extractor failed on a generated valid archive. stderr: "
            f"{result.stderr.decode(errors='replace')}"
        )
        assert os.path.isdir(EXTRACTED_DIR), "Extractor did not create the extracted directory."
        for name, expected_content in files:
            output_path = os.path.join(EXTRACTED_DIR, name)
            assert os.path.isfile(output_path), f"Extractor did not create {name}."
            with open(output_path, "rb") as f:
                actual_content = f.read()
            assert actual_content == expected_content, f"Extracted content for {name} is incorrect."
    finally:
        with open(ARCHIVE_PATH, "wb") as f:
            f.write(original_archive)
        shutil.rmtree(EXTRACTED_DIR, ignore_errors=True)
        run_extractor()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
