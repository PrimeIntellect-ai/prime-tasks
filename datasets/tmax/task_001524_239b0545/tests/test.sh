#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess

PROJECT = "/home/user/pcap_parser"
PARSER = os.path.join(PROJECT, "parser")
CAPTURE = os.path.join(PROJECT, "capture.pcap")
FINAL = os.path.join(PROJECT, "final_output.txt")
EXPECTED = os.path.join(PROJECT, "expected_output.txt")


def run_parser(path):
    result = subprocess.run(
        [PARSER, path],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, (
        f"parser failed for {path} with exit code {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )
    return result.stdout


def extract_udp_payloads(path):
    """Independently derive the expected output from an Ethernet/IPv4 PCAP."""
    data = open(path, "rb").read()
    assert len(data) >= 24, "PCAP global header is truncated"

    magic = data[:4]
    if magic in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1"):
        endian = "<"
    elif magic in (b"\xa1\xb2\xc3\xd4", b"\xa1\xb2\x3c\x4d"):
        endian = ">"
    else:
        raise AssertionError("Unrecognized PCAP byte order")

    offset = 24
    payloads = []
    while offset < len(data):
        assert offset + 16 <= len(data), "Truncated PCAP packet header"
        _, _, captured_len, _ = struct.unpack_from(endian + "IIII", data, offset)
        offset += 16
        assert offset + captured_len <= len(data), "Truncated PCAP packet data"
        packet = data[offset:offset + captured_len]
        offset += captured_len

        if len(packet) < 14 or struct.unpack_from("!H", packet, 12)[0] != 0x0800:
            continue
        ip_start = 14
        if len(packet) < ip_start + 20 or packet[ip_start] >> 4 != 4:
            continue
        ip_header_len = (packet[ip_start] & 0x0f) * 4
        if ip_header_len < 20 or len(packet) < ip_start + ip_header_len:
            continue
        if packet[ip_start + 9] != 17:
            continue
        udp_start = ip_start + ip_header_len
        if len(packet) < udp_start + 8:
            continue
        udp_len = struct.unpack_from("!H", packet, udp_start + 4)[0]
        if udp_len < 8 or len(packet) < udp_start + udp_len:
            continue
        payloads.append(packet[udp_start + 8:udp_start + udp_len])

    return b"".join(payload + b"\n" for payload in payloads)


def ipv4_frame(payload, protocol=17):
    ethernet = bytes.fromhex("00112233445566778899aabb0800")
    if protocol == 17:
        transport = struct.pack("!HHHH", 54321, 12345, 8 + len(payload), 0) + payload
    else:
        transport = payload
    total_len = 20 + len(transport)
    ip_header = struct.pack(
        "!BBHHHBBH4s4s",
        0x45, 0, total_len, 1, 0, 64, protocol, 0,
        bytes((192, 0, 2, 1)), bytes((192, 0, 2, 2)),
    )
    return ethernet + ip_header + transport


def write_pcap(path, packets):
    with open(path, "wb") as f:
        f.write(struct.pack("<IHHIIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
        for index, packet in enumerate(packets):
            f.write(struct.pack("<IIII", 1700000000 + index, 0, len(packet), len(packet)))
            f.write(packet)


def test_00_make_rebuilds_real_parser():
    """Require the repaired Makefile and C++ source to produce the parser."""
    assert os.path.isfile(os.path.join(PROJECT, "Makefile")), "Makefile is missing."
    assert os.path.isfile(os.path.join(PROJECT, "main.cpp")), "main.cpp is missing."
    if os.path.lexists(PARSER):
        os.remove(PARSER)
    result = subprocess.run(
        ["make", "-B"], cwd=PROJECT, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=30, check=False,
    )
    assert result.returncode == 0, (
        "Running make failed:\n" + result.stdout.decode(errors="replace")
    )
    assert os.path.isfile(PARSER), "make did not create the parser binary."
    assert os.access(PARSER, os.X_OK), "The parser produced by make is not executable."
    with open(PARSER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "parser is not a compiled ELF executable."


def test_final_output_exists():
    """Check if the final_output.txt file was created."""
    assert os.path.isfile(FINAL), (
        "The file /home/user/pcap_parser/final_output.txt does not exist. "
        "Did you save the output of your program?"
    )


def test_final_output_content():
    """Verify that the final output exactly matches the expected output."""
    assert os.path.isfile(EXPECTED), f"Expected output file {EXPECTED} is missing."
    with open(EXPECTED, "r") as f:
        expected_content = f.read()
    with open(FINAL, "r") as f:
        final_content = f.read()
    assert final_content == expected_content, (
        "The content of final_output.txt does not match expected_output.txt. "
        "Check your C++ payload extraction logic."
    )


def test_parser_binary_exists():
    """Check if the parser binary was successfully built."""
    assert os.path.isfile(PARSER), (
        "The compiled binary '/home/user/pcap_parser/parser' is missing. "
        "Did you fix the Makefile and successfully run 'make'?"
    )
    assert os.access(PARSER, os.X_OK), (
        "The file '/home/user/pcap_parser/parser' is not executable."
    )


def test_parser_and_final_output_match_capture():
    """Run the compiled artifact and independently validate the supplied capture."""
    derived = extract_udp_payloads(CAPTURE)
    actual = run_parser(CAPTURE)
    assert actual == derived, "parser output for capture.pcap has incorrect UDP payload data."
    with open(FINAL, "rb") as f:
        final_data = f.read()
    assert final_data == derived, "final_output.txt is not the parser's correct capture output."


def test_parser_on_fresh_runtime_capture():
    """Exercise UDP filtering and extraction with unpredictable runtime payloads."""
    first = ("FIRST_" + secrets.token_hex(12)).encode("ascii")
    second = ("SECOND_" + secrets.token_hex(15)).encode("ascii")
    path = "/tmp/verifier_runtime_capture.pcap"
    write_pcap(path, [
        ipv4_frame(first),
        ipv4_frame(b"THIS_NON_UDP_DATA_MUST_BE_IGNORED", protocol=6),
        ipv4_frame(second),
    ])
    derived = extract_udp_payloads(path)
    assert derived == first + b"\n" + second + b"\n"
    assert run_parser(path) == derived, (
        "parser did not correctly filter packets and extract UDP application payloads."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
