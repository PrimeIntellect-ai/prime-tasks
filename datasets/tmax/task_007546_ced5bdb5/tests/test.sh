#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess

HOME = "/home/user"
POISON = bytes([0xBA, 0xAD, 0xF0, 0x0D])
CANONICAL_SENSOR = (
    b"NORMAL_DATA_START..."
    + bytes([0x12, 0x34, 0x56, 0x78]) * 10
    + POISON
    + bytes([0x99, 0x88, 0x77, 0x66]) * 10
    + POISON
    + b"...NORMAL_DATA_END"
)
EXPECTED_CLEANED = CANONICAL_SENSOR.replace(POISON, b"\x00\x00\x00\x00")
EXPECTED_REPORT = f"SUCCESS: Processed {len(CANONICAL_SENSOR)} bytes, status converged."


def test_recover_rs_exists():
    path = os.path.join(HOME, "recover.rs")
    assert os.path.exists(path), f"Missing file: {path}"
    assert os.path.isfile(path), f"Not a file: {path}"


def test_cleaned_data_exists_and_clean():
    sensor_path = os.path.join(HOME, "sensor_data.bin")
    with open(sensor_path, "rb") as f:
        sensor = f.read()
    assert sensor == CANONICAL_SENSOR, "sensor_data.bin was modified"

    path = os.path.join(HOME, "cleaned_data.bin")
    assert os.path.exists(path), f"Missing file: {path}"
    assert os.path.isfile(path), f"Not a file: {path}"

    with open(path, "rb") as f:
        data = f.read()

    assert POISON not in data, "The cleaned_data.bin file still contains the poison bytes (0xBA 0xAD 0xF0 0x0D)."
    assert len(data) == len(sensor), f"Expected cleaned_data.bin to be {len(sensor)} bytes, got {len(data)} bytes."
    assert data == EXPECTED_CLEANED, "cleaned_data.bin changed bytes other than the corrupt sequences"


def test_report_txt_success():
    path = os.path.join(HOME, "report.txt")
    assert os.path.exists(path), f"Missing file: {path}"
    assert os.path.isfile(path), f"Not a file: {path}"

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    assert EXPECTED_REPORT in content, f"The report.txt file does not contain the expected success message. Found: {content.strip()}"


def test_compile_and_execute_recovery_program():
    source = os.path.join(HOME, "recover.rs")
    output = os.path.join(HOME, "cleaned_data.bin")
    executable = "/tmp/recover_verifier_bin"

    if os.path.lexists(executable):
        os.unlink(executable)

    compiled = subprocess.run(
        ["rustc", source, "-o", executable],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compiled.returncode == 0, f"recover.rs did not compile:\n{compiled.stderr.decode(errors='replace')}"
    assert os.path.isfile(executable) and os.access(executable, os.X_OK), "rustc did not produce an executable"

    if os.path.lexists(output):
        os.unlink(output)

    recovered = subprocess.run(
        [executable],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert recovered.returncode == 0, f"Compiled recovery program exited with {recovered.returncode}:\n{recovered.stderr.decode(errors='replace')}"
    assert os.path.isfile(output), "Compiled recovery program did not create cleaned_data.bin"

    with open(output, "rb") as f:
        actual = f.read()
    assert POISON not in actual, "Recovery program left the corrupt sequence in its output"
    assert len(actual) == len(CANONICAL_SENSOR), "Recovery program changed the file size"
    assert actual == EXPECTED_CLEANED, "Recovery program did not replace exactly the corrupt sequences"

    processed = subprocess.run(
        [os.path.join(HOME, "data_processor"), output],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert processed.returncode == 0, f"data_processor did not exit cleanly: {processed.returncode}"
    assert EXPECTED_REPORT.encode() in processed.stdout, f"Unexpected data_processor output: {processed.stdout!r}"

    with open(os.path.join(HOME, "report.txt"), "rb") as f:
        report = f.read()
    assert report == processed.stdout, "report.txt is not the stdout produced by data_processor on cleaned_data.bin"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
