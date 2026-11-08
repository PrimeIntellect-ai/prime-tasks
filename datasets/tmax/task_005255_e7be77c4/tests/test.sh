#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import socket
import pytest

HOST = "127.0.0.1"
PORT = 8888
RAW_CSV = "/app/sensor_raw.csv"


def build_expected():
    aligned = {}
    with open(RAW_CSV, newline="") as f:
        for row in csv.DictReader(f):
            timestamp_ms = int(row["timestamp_ms"])
            value = float(row["value"])
            timestamp_s = math.floor(timestamp_ms / 1000.0 + 0.5)
            if timestamp_s not in aligned or value > aligned[timestamp_s]:
                aligned[timestamp_s] = value

    assert aligned, "The raw sensor CSV contains no data"
    minimum = min(aligned)
    maximum = max(aligned)

    # Forward-fill the complete range before applying the technician's
    # timestamp-specific overrides.
    cleaned = {}
    last_value = None
    for timestamp in range(minimum, maximum + 1):
        if timestamp in aligned:
            last_value = aligned[timestamp]
        assert last_value is not None
        cleaned[timestamp] = last_value

    cleaned[1680000006] = 99.9
    cleaned[1680000015] = 0.5
    return minimum, maximum, cleaned


def send_request(timestamp):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5.0)
        s.connect((HOST, PORT))
        s.sendall(f"{timestamp}\n".encode("ascii"))
        s.shutdown(socket.SHUT_WR)

        response = bytearray()
        while True:
            chunk = s.recv(1024)
            if not chunk:
                break
            response.extend(chunk)
        return bytes(response).decode("utf-8")


def listener_inodes():
    expected_address = "0100007F:22B8"  # 127.0.0.1:8888 in /proc/net/tcp
    found = []
    with open("/proc/net/tcp") as f:
        next(f)
        for line in f:
            fields = line.split()
            if fields[1].upper() == expected_address and fields[3] == "0A":
                found.append(fields[9])
    return found


def listener_pids(inodes):
    targets = {f"socket:[{inode}]" for inode in inodes}
    pids = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f"{fd_dir}/{fd}") in targets:
                        pids.append(int(entry))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return pids


def test_native_server_is_listening_on_required_address():
    inodes = listener_inodes()
    assert inodes, "No TCP server is listening specifically on 127.0.0.1:8888"

    pids = listener_pids(inodes)
    assert pids, "Could not identify the process serving 127.0.0.1:8888"

    disallowed_tools = {
        "python", "python3", "perl", "ruby", "node", "bash", "sh",
        "dash", "nc", "ncat", "netcat", "socat"
    }
    native_server_found = False
    details = []
    for pid in pids:
        try:
            exe_link = os.readlink(f"/proc/{pid}/exe")
            with open(f"/proc/{pid}/exe", "rb") as f:
                magic = f.read(4)
            basename = os.path.basename(exe_link).split(" ", 1)[0]
            details.append(exe_link)
            if magic == b"\x7fELF" and basename not in disallowed_tools:
                native_server_found = True
        except OSError:
            pass

    assert native_server_found, (
        "The listening server must be a compiled native program, not an "
        f"interpreter or generic networking utility; listeners were {details}"
    )


# Preserve the original targeted assertions, correcting timestamp 1680000007:
# overrides apply only to their explicitly dictated timestamps.
@pytest.mark.parametrize("timestamp,expected", [
    (1680000000, "11.50\n"),
    (1680000004, "15.50\n"),
    (1680000005, "15.50\n"),
    (1680000006, "99.90\n"),
    (1680000007, "15.50\n"),
    (1680000015, "0.50\n"),
    (1679999999, "NOT_FOUND\n"),
])
def test_original_required_responses(timestamp, expected):
    assert send_request(timestamp) == expected


def test_every_timestamp_in_processed_range_and_both_boundaries():
    minimum, maximum, cleaned = build_expected()
    timestamps = list(range(minimum, maximum + 1))
    random.Random(734921).shuffle(timestamps)

    for timestamp in timestamps:
        expected = f"{cleaned[timestamp]:.2f}\n"
        assert send_request(timestamp) == expected, (
            f"For timestamp {timestamp}, expected {expected!r}"
        )

    assert send_request(minimum - 1) == "NOT_FOUND\n"
    assert send_request(maximum + 1) == "NOT_FOUND\n"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
