#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest
from scapy.all import Ether, IP, UDP, Raw, wrpcap

APP_DIR = "/home/user/app"
SOURCE_PATH = os.path.join(APP_DIR, "packet_processor.c")
ATTACKER_IP_FILE = "/home/user/attacker_ip.txt"
EXPECTED_IP = "192.168.1.42"


def test_attacker_ip_identified():
    assert os.path.exists(ATTACKER_IP_FILE), f"The file {ATTACKER_IP_FILE} does not exist."
    assert os.path.isfile(ATTACKER_IP_FILE), f"{ATTACKER_IP_FILE} is not a regular file."

    with open(ATTACKER_IP_FILE, "r") as f:
        content = f.read().strip()

    assert content == EXPECTED_IP, f"Expected attacker IP {EXPECTED_IP}, but found '{content}'."


def test_compilation_and_execution():
    assert os.path.exists(APP_DIR), f"Directory {APP_DIR} does not exist."

    clean_proc = subprocess.run(["make", "clean"], cwd=APP_DIR, capture_output=True, text=True)
    assert clean_proc.returncode == 0, f"'make clean' failed:\n{clean_proc.stderr}"

    make_proc = subprocess.run(["make"], cwd=APP_DIR, capture_output=True, text=True)
    assert make_proc.returncode == 0, f"'make' failed to compile the code:\n{make_proc.stderr}"

    binary_path = os.path.join(APP_DIR, "packet_processor")
    assert os.path.exists(binary_path), f"Compiled binary {binary_path} not found after 'make'."
    assert os.path.isfile(binary_path), f"Compiled binary {binary_path} is not a regular file."
    assert os.access(binary_path, os.X_OK), f"Compiled binary {binary_path} is not executable."

    pcap_path = os.path.join(APP_DIR, "traffic.pcap")
    assert os.path.exists(pcap_path), f"PCAP file {pcap_path} is missing."

    try:
        run_proc = subprocess.run(
            [binary_path, pcap_path],
            cwd=APP_DIR,
            capture_output=True,
            text=True,
            timeout=2.0,
        )
        assert run_proc.returncode == 0, (
            f"packet_processor failed with exit code {run_proc.returncode}.\n"
            f"STDOUT:\n{run_proc.stdout}\nSTDERR:\n{run_proc.stderr}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail("packet_processor timed out after 2 seconds. The infinite loop bug is likely not fixed.")


def test_randomized_parsing_and_no_leaks():
    assert os.path.isfile(SOURCE_PATH), f"Source file {SOURCE_PATH} is missing or not a regular file."

    rng = secrets.SystemRandom()
    packets = []
    expected_markers = 0

    # Every packet starts with a zero-length record and has records after it. This
    # requires the parser to advance over the two-byte header rather than stop or spin.
    for packet_index in range(rng.randint(18, 30)):
        records = [(rng.choice([1, 2, 3, 17, 254]), b"")]
        for _ in range(rng.randint(3, 8)):
            record_type = 0xFF if rng.randrange(3) == 0 else rng.choice([1, 2, 3, 17, 254])
            length = rng.randint(0, 24)
            data = bytes(rng.randrange(0, 201) for _ in range(length))
            records.append((record_type, data))
        # Ensure each packet contains a marker after the initial zero-length record.
        records.append((0xFF, bytes(rng.randrange(0, 201) for _ in range(rng.randint(0, 12)))))

        payload = bytearray()
        for record_type, data in records:
            payload.extend((record_type, len(data)))
            payload.extend(data)
            if record_type == 0xFF:
                expected_markers += 1

        packets.append(
            Ether()
            / IP(src=f"172.20.{packet_index // 250}.{packet_index % 250 + 1}", dst="172.21.0.1")
            / UDP(sport=20000 + packet_index, dport=5678)
            / Raw(load=bytes(payload))
        )

    with tempfile.TemporaryDirectory() as tmpdir:
        private_pcap = os.path.join(tmpdir, "private_traffic.pcap")
        sanitized_binary = os.path.join(tmpdir, "packet_processor_asan")
        wrpcap(private_pcap, packets)

        compile_proc = subprocess.run(
            [
                "gcc", "-O1", "-g", "-Wall", "-fno-omit-frame-pointer",
                "-fsanitize=address", "-o", sanitized_binary, SOURCE_PATH, "-lpcap",
            ],
            cwd=APP_DIR,
            capture_output=True,
            text=True,
        )
        assert compile_proc.returncode == 0, (
            "Failed to compile packet_processor.c with AddressSanitizer:\n"
            f"{compile_proc.stdout}\n{compile_proc.stderr}"
        )

        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1:exitcode=86"
        try:
            run_proc = subprocess.run(
                [sanitized_binary, private_pcap],
                cwd=APP_DIR,
                capture_output=True,
                text=True,
                timeout=2.0,
                env=env,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("packet_processor timed out on randomized zero-length records.")

        assert run_proc.returncode == 0, (
            "The sanitized packet processor failed; this may indicate a memory leak or memory error.\n"
            f"Exit code: {run_proc.returncode}\nSTDOUT:\n{run_proc.stdout}\nSTDERR:\n{run_proc.stderr}"
        )
        assert run_proc.stdout.count("Received end marker.") == expected_markers, (
            "packet_processor did not parse all randomized TLV records correctly. "
            f"Expected {expected_markers} end markers, got "
            f"{run_proc.stdout.count('Received end marker.')}\nSTDOUT:\n{run_proc.stdout}"
        )
        assert "Processing complete." in run_proc.stdout, "packet_processor did not complete processing."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
