#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import tempfile


def test_parsed_data_log():
    log_path = "/home/user/parsed_data.log"
    assert os.path.isfile(log_path), f"Expected output file {log_path} does not exist. Did you redirect the output?"

    with open(log_path, 'r') as f:
        content = f.read().strip()

    expected = (
        "Sensor 10: 25\n"
        "Status: OK\n"
        "Malformed packet: length 50 exceeds payload\n"
        "Sensor 12: 26"
    )

    assert content == expected, f"Content of {log_path} does not match expected output.\nExpected:\n{expected}\nGot:\n{content}"


def test_script_execution():
    script_path = "/home/user/parse_pcap.py"
    pcap_path = "/home/user/traffic.pcap"

    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(pcap_path), f"PCAP file {pcap_path} does not exist."

    result = subprocess.run(["python3", script_path, pcap_path], capture_output=True, text=True)

    assert result.returncode == 0, f"Script crashed or returned non-zero exit code. Stderr:\n{result.stderr}"

    expected = (
        "Sensor 10: 25\n"
        "Status: OK\n"
        "Malformed packet: length 50 exceeds payload\n"
        "Sensor 12: 26"
    )

    assert result.stdout.strip() == expected, "Script output does not match expected output when run directly."


def write_pcap(path, payloads):
    with open(path, "wb") as f:
        f.write(struct.pack("<IHHIIII", 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1))
        for payload in payloads:
            packet = (b"\x00" * 42) + payload
            f.write(struct.pack("<IIII", 0, 0, len(packet), len(packet)))
            f.write(packet)


def test_handles_other_malformed_lengths_and_continues():
    script_path = "/home/user/parse_pcap.py"
    first_id = 1000 + secrets.randbelow(100000)
    first_value = 1000 + secrets.randbelow(100000)
    last_id = 200000 + secrets.randbelow(100000)
    last_value = 200000 + secrets.randbelow(100000)
    status = secrets.token_hex(4).upper().encode("ascii")
    fragment = secrets.token_hex(3).upper().encode("ascii")
    claimed_length = 20 + secrets.randbelow(200)

    payloads = [
        struct.pack(">BII", 1, first_id, first_value),
        struct.pack(">BB", 2, claimed_length) + fragment,
        struct.pack(">BB", 2, len(status)) + status,
        struct.pack(">BII", 1, last_id, last_value),
    ]
    expected = "\n".join([
        f"Sensor {first_id}: {first_value}",
        f"Malformed packet: length {claimed_length} exceeds payload",
        f"Status: {status.decode('ascii')}",
        f"Sensor {last_id}: {last_value}",
    ])

    with tempfile.TemporaryDirectory() as tmpdir:
        pcap_path = os.path.join(tmpdir, secrets.token_hex(8) + ".pcap")
        write_pcap(pcap_path, payloads)
        result = subprocess.run(
            ["python3", script_path, pcap_path],
            capture_output=True,
            text=True,
            timeout=10,
        )

    assert result.returncode == 0, f"Script failed on generated pcap. Stderr:\n{result.stderr}"
    assert result.stdout.strip() == expected, (
        "Script did not parse a generated malformed packet and subsequent valid packets correctly.\n"
        f"Expected:\n{expected}\nGot:\n{result.stdout.strip()}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
