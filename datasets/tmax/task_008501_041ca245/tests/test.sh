#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import time

DATA_PATH = "/home/user/data.out"
SOURCE_PATH = "/home/user/telemetry_ingest.cpp"
BINARY_PATH = "/home/user/telemetry_ingest"
PCAP_PATH = "/home/user/traffic.pcap"

ORIGINAL_LINES = [
    "Sensor 101: 12345.678901",
    "Sensor 102: 98765.432109",
    "Sensor 103: 0.000001",
]


def read_output():
    assert os.path.isfile(DATA_PATH), f"Expected output file {DATA_PATH} does not exist. The program may not have run successfully or still writes to the wrong path."
    with open(DATA_PATH, "r") as f:
        return f.read().strip().splitlines()


def assert_output(expected_lines):
    content = read_output()
    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines in {DATA_PATH}, but found {len(content)}."
    for i, (actual, expected) in enumerate(zip(content, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected: '{expected}', Got: '{actual}'. Precision loss may still be present."


def run_ingestor():
    result = subprocess.run(
        [BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"The compiled ingestor exited with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def make_pcap(records):
    global_header = struct.pack('<IHHIIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1)
    chunks = [global_header]
    for sensor_id, value in records:
        eth = b'\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x08\x00'
        ip = b'\x45\x00\x00\x28\x00\x00\x40\x00\x40\x11\x00\x00\x7f\x00\x00\x01\x7f\x00\x00\x01'
        udp = b'\x30\x39\x30\x39\x00\x14\x00\x00'
        packet = eth + ip + udp + struct.pack('>Id', sensor_id, value)
        chunks.append(struct.pack('<IIII', int(time.time()), 0, len(packet), len(packet)))
        chunks.append(packet)
    return b''.join(chunks)


def test_data_out_exists():
    assert os.path.isfile(DATA_PATH), f"Expected output file {DATA_PATH} does not exist. The program may not have run successfully or still writes to the wrong path."


def test_data_out_contents():
    assert_output(ORIGINAL_LINES)


def test_telemetry_ingest_cpp_fixes():
    assert os.path.isfile(SOURCE_PATH), f"Source file {SOURCE_PATH} is missing."
    with open(SOURCE_PATH, "r") as f:
        content = f.read()
    assert "/home/user/data.out" in content, "The source code does not contain the correct output path '/home/user/data.out'."
    assert "/root/telemetry.out" not in content, "The source code still contains the buggy output path '/root/telemetry.out'."
    assert "double" in content, "The source code does not seem to use 'double' to fix the precision loss."


def test_recompiled_program_processes_original_and_unseen_pcap():
    compile_result = subprocess.run(
        ["g++", "-o", BINARY_PATH, SOURCE_PATH, "-lpcap"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"Recompilation failed: {compile_result.stderr}"
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK), "Compilation did not produce an executable ingestor."

    if os.path.exists(DATA_PATH):
        os.unlink(DATA_PATH)
    run_ingestor()
    assert_output(ORIGINAL_LINES)

    with open(PCAP_PATH, "rb") as f:
        original_pcap = f.read()

    ids = []
    while len(ids) < 3:
        candidate = 1000 + secrets.randbelow(4_000_000_000)
        if candidate <= 0xffffffff and candidate not in ids:
            ids.append(candidate)
    base = 20000 + secrets.randbelow(50000)
    records = [
        (ids[0], base + 0.67890123),
        (ids[1], base + 1000 + 0.43210987),
        (ids[2], base + 2000 + 0.24681357),
    ]
    expected = [f"Sensor {sensor_id}: {value:.6f}" for sensor_id, value in records]

    try:
        with open(PCAP_PATH, "wb") as f:
            f.write(make_pcap(records))
        if os.path.exists(DATA_PATH):
            os.unlink(DATA_PATH)
        run_ingestor()
        assert_output(expected)
    finally:
        with open(PCAP_PATH, "wb") as f:
            f.write(original_pcap)

    if os.path.exists(DATA_PATH):
        os.unlink(DATA_PATH)
    run_ingestor()
    assert_output(ORIGINAL_LINES)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
