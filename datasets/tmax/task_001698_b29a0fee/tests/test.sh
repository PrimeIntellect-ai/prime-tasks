#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import struct
import secrets
import string
import subprocess
import tempfile
import importlib.util
import base64

SCRIPT_PATH = "/home/user/parse_packet.py"
MAGIC = b'\xde\xad\xbe\xef'
ALPHABET = string.ascii_letters + string.digits


def random_text(min_length=7, extra_length=18):
    length = min_length + secrets.randbelow(extra_length + 1)
    return ''.join(secrets.choice(ALPHABET) for _ in range(length))


def make_case(direction):
    expected = random_text()
    expected_bytes = expected.encode('ascii')

    if direction == "backward":
        leading = random_text().encode('ascii') + b'\x00'
        target_index = len(leading)
        before_magic = leading + expected_bytes + b'\x00' + random_text().encode('ascii') + b'\x00'
        magic_index = len(before_magic)
        offset = target_index - (magic_index + 8)
        packet = before_magic + MAGIC + struct.pack('<i', offset) + random_text().encode('ascii')
        assert offset < 0
    elif direction == "forward":
        leading = random_text().encode('ascii') + b'\x00'
        magic_index = len(leading)
        gap = random_text().encode('ascii') + b'\x00' + random_text().encode('ascii') + b'\x00'
        offset = len(gap)
        packet = leading + MAGIC + struct.pack('<i', offset) + gap + expected_bytes + b'\x00' + random_text().encode('ascii')
        assert offset > 0
    else:
        leading = random_text().encode('ascii') + b'\x00'
        packet = leading + MAGIC + struct.pack('<i', 0) + expected_bytes + b'\x00' + random_text().encode('ascii')

    return packet, expected


DYNAMIC_CASES = [make_case("backward") for _ in range(6)]
DYNAMIC_CASES += [make_case("forward") for _ in range(6)]
DYNAMIC_CASES.append(make_case("zero"))


def load_parser(module_name):
    spec = importlib.util.spec_from_file_location(module_name, SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def test_flag_file_exists_and_correct():
    flag_path = "/home/user/flag.txt"
    assert os.path.isfile(flag_path), f"Expected flag file {flag_path} does not exist."

    with open(flag_path, "r") as f:
        content = f.read()

    expected_flag = "FLAG{signed_int_fix}"
    assert content == expected_flag, f"Flag file content is incorrect. Expected '{expected_flag}', got '{content}'."


def test_parse_packet_script_fixed():
    script_path = "/home/user/parse_packet.py"
    assert os.path.isfile(script_path), f"Parser script {script_path} is missing."

    # Load the module to test the parse function
    spec = importlib.util.spec_from_file_location("parse_packet", script_path)
    parse_packet = importlib.util.module_from_spec(spec)
    sys.modules["parse_packet"] = parse_packet
    spec.loader.exec_module(parse_packet)

    assert hasattr(parse_packet, "parse"), "parse_packet.py is missing the 'parse' function."

    # The original base64 payload from the log
    b64_payload = "RkxBR3tzaWduZWRfaW50X2ZpeH0A3q2+7+P///8="
    binary_payload = base64.b64decode(b64_payload)

    try:
        result = parse_packet.parse(binary_payload)
    except Exception as e:
        assert False, f"parse_packet.parse() raised an exception: {e}"

    assert result == "FLAG{signed_int_fix}", f"parse_packet.parse() returned incorrect result: {result}. The script might not be correctly handling signed integers."


def test_parse_uses_signed_relative_offsets_on_dynamic_packets():
    parse_packet = load_parser("parse_packet_dynamic")
    assert hasattr(parse_packet, "parse"), "parse_packet.py is missing the 'parse' function."

    for packet, expected in DYNAMIC_CASES:
        try:
            result = parse_packet.parse(packet)
        except Exception as e:
            assert False, f"parse_packet.parse() raised an exception on a generated valid packet: {e}"
        assert result == expected, (
            f"parse_packet.parse() did not follow the packet's signed relative offset: "
            f"expected {expected!r}, got {result!r}"
        )

    no_magic = random_text(30, 20).encode('ascii')
    assert parse_packet.parse(no_magic) == "No magic found"


def test_parser_command_line_execution_on_crash_payload():
    binary_payload = base64.b64decode("RkxBR3tzaWduZWRfaW50X2ZpeH0A3q2+7+P///8=")
    path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False) as packet_file:
            packet_file.write(binary_payload)
            path = packet_file.name

        completed = subprocess.run(
            [sys.executable, SCRIPT_PATH, path],
            capture_output=True,
            text=True,
            timeout=5,
        )
        assert completed.returncode == 0, f"Parser command failed: {completed.stderr}"
        assert completed.stdout == "FLAG{signed_int_fix}\n", (
            f"Parser command produced incorrect output: {completed.stdout!r}"
        )
    finally:
        if path is not None and os.path.exists(path):
            os.unlink(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
