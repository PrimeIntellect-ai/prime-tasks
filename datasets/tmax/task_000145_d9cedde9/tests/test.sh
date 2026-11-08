#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import py_compile
import shutil
import stat
import subprocess
import sys
import tempfile

from scapy.all import Ether, IP, TCP, wrpcap
from scapy.utils import RawPcapReader

SCRIPT = "/home/user/pcap_processor.py"
PCAP_DIR = "/home/user/pcaps"
RESULT = "/home/user/result.txt"


def pcap_total(directory):
    total = 0
    for path in glob.glob(os.path.join(directory, "*.pcap")):
        reader = RawPcapReader(path)
        try:
            for packet_data, _metadata in reader:
                total += len(packet_data)
        finally:
            reader.close()
    return total


def run_processor(expected):
    if os.path.exists(RESULT):
        os.remove(RESULT)
    completed = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f"pcap_processor.py exited with {completed.returncode}: {completed.stderr}"
    )
    assert os.path.isfile(RESULT), "pcap_processor.py did not create /home/user/result.txt"
    with open(RESULT, "r") as f:
        content = f.read().strip()
    assert content == str(expected), f"Expected {expected}, but script wrote {content!r}"


def clear_directory(directory):
    for name in os.listdir(directory):
        path = os.path.join(directory, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.remove(path)


def write_case(files):
    clear_directory(PCAP_DIR)
    for filename, payload_size, count in files:
        packets = [Ether()/IP()/TCP(sport=1234, dport=4321)/(bytes([65 + payload_size % 20]) * payload_size) for _ in range(count)]
        wrpcap(os.path.join(PCAP_DIR, filename), packets)


def test_result_file_exists():
    """Check if the result file was created."""
    assert os.path.isfile("/home/user/result.txt"), "The file /home/user/result.txt does not exist. Did you run the script?"


def test_result_file_content():
    """Check if the result file contains the correct total bytes."""
    assert os.path.isfile("/home/user/result.txt"), "The file /home/user/result.txt does not exist."
    with open("/home/user/result.txt", "r") as f:
        content = f.read().strip()

    assert content == "381000", f"Expected total bytes to be '381000', but got '{content}'. The script might still have bugs."


def test_processor_is_fixed_and_reliable():
    assert os.path.isfile(SCRIPT), f"Missing required script: {SCRIPT}"
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"{SCRIPT} is not a regular file"
    py_compile.compile(SCRIPT, doraise=True)

    original_expected = pcap_total(PCAP_DIR)
    assert original_expected == 381000, "The supplied capture corpus was modified"

    # Re-execute against the original corpus repeatedly to detect stale output
    # and intermittent aggregation failures.
    for _ in range(4):
        run_processor(original_expected)

    backup_parent = tempfile.mkdtemp(prefix="pcap-verifier-")
    backup = os.path.join(backup_parent, "original_pcaps")
    os.replace(PCAP_DIR, backup)
    os.mkdir(PCAP_DIR)
    try:
        cases = [
            [("capture with spaces.pcap", 17, 7)],
            [
                ("alpha.pcap", 11, 23),
                ("beta file.pcap", 29, 19),
                ("gamma.pcap", 47, 17),
                ("delta file.pcap", 83, 13),
                ("epsilon.pcap", 101, 11),
                ("zeta file.pcap", 137, 9),
                ("eta.pcap", 163, 7),
                ("theta file.pcap", 211, 5),
            ],
        ]
        for files in cases:
            write_case(files)
            expected = pcap_total(PCAP_DIR)
            assert expected != 381000
            for _ in range(4):
                run_processor(expected)
    finally:
        shutil.rmtree(PCAP_DIR, ignore_errors=True)
        os.replace(backup, PCAP_DIR)
        shutil.rmtree(backup_parent, ignore_errors=True)

    # Leave and verify the required result for the original supplied captures.
    run_processor(original_expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
