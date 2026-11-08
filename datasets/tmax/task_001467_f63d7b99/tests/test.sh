#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import struct
import subprocess
import time

import pytest

PROJECT = "/home/user/telemetry_processor"
BINARY = PROJECT + "/target/release/telemetry_processor"
INGRESS = "/home/user/data/ingress.pcap"


def get_expected_rows(pcap_path):
    rows = []
    with open(pcap_path, "rb") as f:
        magic = f.read(4)
        if magic == b"\xd4\xc3\xb2\xa1":
            endian = "<"
        elif magic == b"\xa1\xb2\xc3\xd4":
            endian = ">"
        else:
            raise AssertionError("Invalid PCAP magic")

        f.seek(24)
        while True:
            hdr = f.read(16)
            if not hdr:
                break
            assert len(hdr) == 16, "Truncated PCAP packet header"
            _, _, incl_len, _ = struct.unpack(f"{endian}IIII", hdr)
            pkt_data = f.read(incl_len)
            assert len(pkt_data) == incl_len, "Truncated PCAP packet"
            payload = pkt_data[-16:]
            assert len(payload) >= 3, "Packet payload is too short"
            b0, b1, b2 = payload[0], payload[1], payload[2]
            score = (b0 ^ 0x5A) * 2.5 + (b1 << 2) - math.sqrt(b2)
            rows.append((b0, score))
    return rows


def read_output(path):
    assert os.path.isfile(path), f"Output file {path} does not exist"
    parsed = []
    with open(path, newline="") as f:
        rows = list(csv.reader(f))

    for index, row in enumerate(rows):
        assert len(row) >= 2, "CSV must contain at least two columns: packet_id and score"
        try:
            packet_id_number = float(row[0].strip())
            score = float(row[1].strip())
        except ValueError:
            if index == 0:
                continue
            raise AssertionError(f"Non-numeric CSV data on row {index + 1}")
        assert math.isfinite(packet_id_number) and packet_id_number.is_integer(), \
            f"Invalid packet ID on row {index + 1}"
        assert math.isfinite(score), f"Invalid score on row {index + 1}"
        parsed.append((int(packet_id_number), score))
    return parsed


def assert_correct_output(path, expected):
    actual = read_output(path)
    assert len(actual) == len(expected), \
        f"Expected {len(expected)} rows, but found {len(actual)} valid rows in the CSV"

    actual_ids = [row[0] for row in actual]
    expected_ids = [row[0] for row in expected]
    assert actual_ids == expected_ids, \
        f"Packet IDs or their ordering are incorrect: expected {expected_ids}, got {actual_ids}"

    mse = sum((actual[i][1] - expected[i][1]) ** 2 for i in range(len(expected))) / len(expected)
    assert mse <= 1e-5, \
        f"Mean Squared Error (MSE) is {mse:.6f}, expected 0.0. The formula logic is still incorrect"


def write_challenge_pcap(path):
    payload_prefixes = [
        (203, 17, 250),
        (44, 199, 1),
        (127, 0, 81),
        (5, 254, 169),
        (238, 73, 2),
        (91, 128, 225),
    ]
    with open(path, "wb") as f:
        f.write(struct.pack("<IHHIIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
        for sequence, (b0, b1, b2) in enumerate(payload_prefixes):
            payload = bytes([b0, b1, b2]) + bytes(13)
            ethernet = bytes.fromhex("00112233445566778899aabb0800")
            total_len = 20 + 8 + len(payload)
            ip = struct.pack(
                "!BBHHHBBH4s4s",
                0x45, 0, total_len, sequence, 0, 64, 17, 0,
                bytes([10, 0, 0, 1]), bytes([192, 168, 1, 1]),
            )
            udp = struct.pack("!HHHH", 4000 + sequence, 1234, 8 + len(payload), 0)
            packet = ethernet + ip + udp + payload
            f.write(struct.pack("<IIII", sequence, 0, len(packet), len(packet)))
            f.write(packet)


@pytest.fixture(scope="session", autouse=True)
def verify_release_build():
    assert os.path.isfile(BINARY), \
        f"Compiled release binary not found at {BINARY}. Did you compile with cargo build --release?"
    assert os.access(BINARY, os.X_OK), "Release artifact is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Release artifact must be a compiled executable"

    result = subprocess.run(
        ["/root/.cargo/bin/cargo", "build", "--release"],
        cwd=PROJECT,
        capture_output=True,
        timeout=180,
    )
    assert result.returncode == 0, \
        "Rust project does not build in release mode:\n" + result.stderr.decode(errors="replace")


def test_output_csv_mse_and_packet_ids():
    assert_correct_output("/home/user/output.csv", get_expected_rows(INGRESS))


def test_execution_time_and_generated_output():
    output_path = "/home/user/test_perf_output.csv"
    if os.path.exists(output_path):
        os.remove(output_path)

    start_time = time.perf_counter()
    result = subprocess.run([BINARY, INGRESS, output_path], capture_output=True, timeout=5)
    exec_time = time.perf_counter() - start_time

    assert result.returncode == 0, \
        f"Binary execution failed with return code {result.returncode}\nStderr: {result.stderr.decode(errors='replace')}"
    assert exec_time <= 2.0, \
        f"Execution time was {exec_time:.2f} seconds, expected <= 2.0 seconds"
    assert_correct_output(output_path, get_expected_rows(INGRESS))


def test_processor_on_independent_pcap(tmp_path):
    pcap_path = str(tmp_path / "challenge.pcap")
    output_path = str(tmp_path / "challenge.csv")
    write_challenge_pcap(pcap_path)

    result = subprocess.run([BINARY, pcap_path, output_path], capture_output=True, timeout=5)
    assert result.returncode == 0, \
        f"Binary failed on challenge PCAP: {result.stderr.decode(errors='replace')}"
    assert_correct_output(output_path, get_expected_rows(pcap_path))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
