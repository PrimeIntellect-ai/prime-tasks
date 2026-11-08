#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import math
import os
import random
import re
import socket
import subprocess

import pytest

VIDEO = "/app/sensor_feed.mp4"
SEARCH_ROOTS = [
    "/home/user", "/home/oai/share", "/app", "/tmp", "/root",
    "/workspace", "/frames"
]


def derive_expected_probabilities():
    probe = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x",
            VIDEO,
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    width, height = map(int, probe.stdout.strip().split("x"))
    frame_size = width * height * 3

    decoded = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", VIDEO, "-vsync", "0",
            "-f", "rawvideo", "-pix_fmt", "rgb24", "-",
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout

    assert decoded and len(decoded) % frame_size == 0, "Could not decode complete RGB frames"
    probabilities = []
    for offset in range(0, len(decoded), frame_size):
        frame = decoded[offset:offset + frame_size]
        weighted_sum = 0.0
        for i in range(0, frame_size, 3):
            weighted_sum += 0.299 * frame[i] + 0.587 * frame[i + 1] + 0.114 * frame[i + 2]
        x = weighted_sum / (width * height)

        log_active = (
            math.log(0.85) - math.log(30.0) - 0.5 * math.log(2.0 * math.pi)
            - 0.5 * ((x - 110.0) / 30.0) ** 2
        )
        log_inactive = (
            math.log(0.15) - math.log(2.0) - 0.5 * math.log(2.0 * math.pi)
            - 0.5 * (x / 2.0) ** 2
        )
        difference = log_inactive - log_active
        if difference > 700:
            probability = 0.0
        elif difference < -700:
            probability = 1.0
        else:
            probability = 1.0 / (1.0 + math.exp(difference))
        probabilities.append(probability)

    return decoded, probabilities


DECODED_VIDEO, EXPECTED = derive_expected_probabilities()
EXPECTED_INACTIVE = sum(probability < 0.5 for probability in EXPECTED)


def send_command(cmd: str) -> str:
    try:
        with socket.create_connection(("127.0.0.1", 9090), timeout=5.0) as sock:
            sock.settimeout(5.0)
            sock.sendall(cmd.encode("utf-8"))
            response = b""
            while b"\n" not in response and len(response) < 1024:
                chunk = sock.recv(1024)
                if not chunk:
                    break
                response += chunk
            return response.decode("utf-8")
    except Exception as exc:
        pytest.fail(f"Failed to connect or communicate with server on 127.0.0.1:9090: {exc}")


def find_submission_files():
    source_files = []
    image_counts = {}
    for root in SEARCH_ROOTS:
        if not os.path.isdir(root):
            continue
        for directory, subdirs, files in os.walk(root):
            subdirs[:] = [name for name in subdirs if name not in {".cache", ".git"}]
            for name in files:
                lower = name.lower()
                path = os.path.join(directory, name)
                if lower.endswith((".cpp", ".cc", ".cxx")):
                    try:
                        if os.path.getsize(path) > 0:
                            source_files.append(path)
                    except OSError:
                        pass
                if lower.endswith((".png", ".jpg", ".jpeg")):
                    image_counts[directory] = image_counts.get(directory, 0) + 1
    return source_files, image_counts


def listener_pids():
    inodes = set()
    with open("/proc/net/tcp", "r", encoding="ascii") as handle:
        next(handle)
        for line in handle:
            fields = line.split()
            local_address = fields[1]
            state = fields[3]
            address, port = local_address.split(":")
            if address == "0100007F" and int(port, 16) == 9090 and state == "0A":
                inodes.add(fields[9])

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(entry))
        except OSError:
            continue
    return pids


def test_cpp_artifact_and_extracted_frames_exist():
    source_files, image_counts = find_submission_files()
    assert source_files, "No nonempty C++ source file was found in a submission-writable location"
    assert any(count >= len(EXPECTED) for count in image_counts.values()), (
        f"No directory containing all {len(EXPECTED)} extracted PNG/JPEG frames was found"
    )

    pids = listener_pids()
    assert pids, "No process is listening on 127.0.0.1:9090"
    elf_listener = False
    for pid in pids:
        try:
            with open(f"/proc/{pid}/exe", "rb") as executable:
                if executable.read(4) == b"\x7fELF":
                    elf_listener = True
                    break
        except OSError:
            continue
    assert elf_listener, "The TCP listener is not a compiled native executable"


def test_frame_30_inactive():
    response = send_command("FRAME 30\n")
    match = re.match(r"^PROB:\s+([0-9.]+)\n?$", response)
    assert match is not None, f"Unexpected response format for FRAME 30: {response!r}"
    prob = float(match.group(1))
    assert prob < 0.0010, f"Expected probability for frame 30 to be < 0.0010, got {prob}"


def test_count_inactive():
    response = send_command("COUNT_INACTIVE\n")
    assert response.strip() == "INACTIVE: 11", f"Expected 'INACTIVE: 11', got {response!r}"


def test_frame_5_active():
    response = send_command("FRAME 5\n")
    match = re.match(r"^PROB:\s+([0-9.]+)\n?$", response)
    assert match is not None, f"Unexpected response format for FRAME 5: {response!r}"
    prob = float(match.group(1))
    assert prob > 0.9990, f"Expected probability for frame 5 to be > 0.9990, got {prob}"


def test_every_frame_matches_independently_derived_posterior():
    indices = list(range(len(EXPECTED)))
    seed = int.from_bytes(hashlib.sha256(DECODED_VIDEO).digest()[:8], "big")
    random.Random(seed).shuffle(indices)

    for index in indices:
        response = send_command(f"FRAME {index}\n")
        assert re.fullmatch(r"PROB: [0-9]+\.[0-9]{4}\n", response), (
            f"FRAME {index} did not use the exact four-decimal response format: {response!r}"
        )
        assert response == f"PROB: {EXPECTED[index]:.4f}\n", (
            f"Incorrect posterior for frame {index}: expected "
            f"{EXPECTED[index]:.4f}, got {response!r}"
        )


def test_derived_inactive_count():
    response = send_command("COUNT_INACTIVE\n")
    assert response == f"INACTIVE: {EXPECTED_INACTIVE}\n", (
        f"Expected independently derived inactive count {EXPECTED_INACTIVE}, got {response!r}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
