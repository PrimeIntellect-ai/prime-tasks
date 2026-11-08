#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import struct
import subprocess
import time

SERVER_DIR = "/home/user/server_src"
SERVER_PATH = os.path.join(SERVER_DIR, "server")
MAKEFILE_PATH = os.path.join(SERVER_DIR, "Makefile")
PCAP_PATH = "/home/user/crash.pcap"
REPORT_PATH = "/home/user/report.txt"
EXPECTED_PAYLOAD = "OVERFLOW_PAYLOAD_ABCDEFGHIJKLMNOPQRSTUVWXYZ123456789"


def extract_udp_payload(path, destination_port):
    with open(path, "rb") as f:
        data = f.read()

    assert len(data) >= 24, "PCAP is too short to contain a global header."
    magic = data[:4]
    if magic in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1"):
        endian = "<"
    elif magic in (b"\xa1\xb2\xc3\xd4", b"\xa1\xb2\x3c\x4d"):
        endian = ">"
    else:
        raise AssertionError("Unsupported PCAP byte order or format.")

    network = struct.unpack(endian + "I", data[20:24])[0]
    assert network == 1, "Expected an Ethernet PCAP."

    offset = 24
    while offset + 16 <= len(data):
        _, _, included_length, _ = struct.unpack(
            endian + "IIII", data[offset:offset + 16]
        )
        offset += 16
        packet = data[offset:offset + included_length]
        offset += included_length
        if len(packet) < 14 or packet[12:14] != b"\x08\x00":
            continue

        ip = packet[14:]
        if len(ip) < 20 or ip[0] >> 4 != 4 or ip[9] != 17:
            continue
        ihl = (ip[0] & 0x0f) * 4
        if ihl < 20 or len(ip) < ihl + 8:
            continue

        udp = ip[ihl:]
        _, dst_port, udp_length = struct.unpack(">HHH", udp[:6])
        if dst_port != destination_port or udp_length < 8:
            continue
        assert len(udp) >= udp_length, "Captured UDP packet is truncated."
        return udp[8:udp_length]

    raise AssertionError(f"No UDP packet for destination port {destination_port} was found.")


def test_makefile_builds_real_server():
    assert os.path.isfile(MAKEFILE_PATH), f"The Makefile was not found at {MAKEFILE_PATH}."
    with open(MAKEFILE_PATH, "r") as f:
        makefile = f.read()
    assert re.search(r"(?<!\S)-lm(?!\S)", makefile), "The Makefile does not include the required -lm linker flag."

    dry_run = subprocess.run(
        ["make", "-n", "-B", "server"], cwd=SERVER_DIR,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15
    )
    assert dry_run.returncode == 0, f"Makefile dry run failed:\n{dry_run.stdout}"
    assert re.search(r"(?<!\S)-lm(?!\S)", dry_run.stdout), "The resolved server build command does not link with -lm."
    assert "server.c" in dry_run.stdout, "The server target is not built from server.c."
    assert re.search(r"(?:^|[;&|\n]\s*|\s)(?:gcc|cc)(?:\s|$)", dry_run.stdout), "The server target does not invoke a C compiler."

    if os.path.lexists(SERVER_PATH):
        os.remove(SERVER_PATH)
    build = subprocess.run(
        ["make", "-B", "server"], cwd=SERVER_DIR,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert build.returncode == 0, f"Building the server failed:\n{build.stdout}"

    # Preserve the original server artifact assertions.
    assert os.path.isfile(SERVER_PATH), f"The server binary was not found at {SERVER_PATH}. Did you run make?"
    assert os.access(SERVER_PATH, os.X_OK), f"The file at {SERVER_PATH} is not executable."
    with open(SERVER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The built server is not an ELF binary."

    symbols = subprocess.run(
        ["nm", SERVER_PATH], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=10
    )
    assert symbols.returncode == 0, f"Could not inspect server symbols:\n{symbols.stdout}"
    assert re.search(r"\blog_message$", symbols.stdout, re.MULTILINE), "The built server does not contain log_message."


def test_server_crashes_in_reported_function_on_pcap_payload():
    payload = extract_udp_payload(PCAP_PATH, 9000)
    assert payload.decode("utf-8") == EXPECTED_PAYLOAD

    proc = subprocess.Popen(
        ["gdb", "--batch", "--quiet", "-ex", "set pagination off", "-ex", "run", "-ex", "bt", "--args", SERVER_PATH],
        cwd=SERVER_DIR, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # Repeated sends tolerate the short interval while gdb starts and the server binds.
        for _ in range(30):
            if proc.poll() is not None:
                break
            sock.sendto(payload, ("127.0.0.1", 9000))
            time.sleep(0.1)
        try:
            output, _ = proc.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            output, _ = proc.communicate()
            raise AssertionError(f"The server did not terminate after receiving the PCAP payload.\n{output}")
    finally:
        sock.close()
        if proc.poll() is None:
            proc.kill()
            proc.wait()

    assert re.search(r"Program received signal SIGSEGV", output), f"The PCAP payload did not reproduce a segmentation fault under gdb:\n{output}"
    assert re.search(r"\blog_message\b", output), f"The gdb crash output does not identify log_message:\n{output}"


def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"The report file {REPORT_PATH} is missing."


def test_report_content():
    with open(REPORT_PATH, "r") as f:
        raw_content = f.read()
    content = raw_content.strip()
    lines = content.split("\n")
    assert len(lines) == 3, f"Expected exactly 3 lines in report.txt, but found {len(lines)}."

    # Preserve the original exact answer assertions.
    assert lines[0].strip() == "-lm", f"Line 1 is incorrect. Expected '-lm', got '{lines[0].strip()}'."
    assert lines[1].strip() == EXPECTED_PAYLOAD, f"Line 2 is incorrect. Expected '{EXPECTED_PAYLOAD}', got '{lines[1].strip()}'."
    assert lines[2].strip() == "log_message", f"Line 3 is incorrect. Expected 'log_message', got '{lines[2].strip()}'."

    pcap_payload = extract_udp_payload(PCAP_PATH, 9000).decode("utf-8")
    assert lines[1] == pcap_payload, "Report payload does not exactly match the UDP payload derived from crash.pcap."
    expected_report = f"-lm\n{pcap_payload}\nlog_message"
    assert raw_content in (expected_report, expected_report + "\n"), "report.txt contains extra whitespace, text, or empty lines."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
