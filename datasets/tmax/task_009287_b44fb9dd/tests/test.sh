#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess

EXPECTED_PARSER = b"""import sys
import struct

def parse_file(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()

    if not data.startswith(b'MALW'):
        return

    idx = 4
    if idx + 2 > len(data):
        return

    num_chunks = struct.unpack('<H', data[idx:idx+2])[0]
    idx += 2

    for _ in range(num_chunks):
        if idx >= len(data):
            break
        ctype = data[idx]
        idx += 1

        if idx + 2 > len(data):
            break
        clen = struct.unpack('<H', data[idx:idx+2])[0]
        idx += 2

        if ctype == 0x42:
            if idx + 4 > len(data):
                break
            offset = struct.unpack('<I', data[idx:idx+4])[0]
            # Vulnerability: tries to unpack 8 bytes from an arbitrary offset that might be out of bounds
            val = struct.unpack('<d', data[offset:offset+8])[0]
            print(f"Extracted double: {val}")
            idx += 4
        else:
            idx += clen

if __name__ == '__main__':
    if len(sys.argv) > 1:
        parse_file(sys.argv[1])
"""


def test_minimal_crash_bin_exists_and_size():
    minimal_bin_path = '/home/user/minimal_crash.bin'
    assert os.path.isfile(minimal_bin_path), f"Expected file {minimal_bin_path} does not exist."

    size = os.path.getsize(minimal_bin_path)
    assert size == 13, f"Expected minimal_crash.bin to be exactly 13 bytes, but got {size} bytes."


def test_crash_info_txt():
    crash_info_path = '/home/user/crash_info.txt'
    assert os.path.isfile(crash_info_path), f"Expected file {crash_info_path} does not exist."

    with open(crash_info_path, 'r') as f:
        content = f.read().strip()

    assert content == '13', f"Expected crash_info.txt to contain exactly '13', but got '{content}'."


def test_minimal_crash_triggers_exact_error():
    parser_path = '/home/user/parser.py'
    minimal_bin_path = '/home/user/minimal_crash.bin'

    assert os.path.isfile(parser_path), "parser.py is missing."
    assert os.path.isfile(minimal_bin_path), "minimal_crash.bin is missing."

    result = subprocess.run(
        ['python3', parser_path, minimal_bin_path],
        capture_output=True,
        text=True
    )

    # The script should crash (non-zero exit code)
    assert result.returncode != 0, "Expected parser.py to crash, but it exited normally."

    # The error message should be the specific struct.error
    expected_error = "struct.error: unpack requires a buffer of 8 bytes"
    assert expected_error in result.stderr, f"Expected stderr to contain '{expected_error}', but got:\n{result.stderr}"


def test_parser_unmodified():
    parser_path = '/home/user/parser.py'
    assert os.path.isfile(parser_path), "parser.py is missing."

    with open(parser_path, 'r') as f:
        content = f.read()

    assert "val = struct.unpack('<d', data[offset:offset+8])[0]" in content, "parser.py appears to have been modified."
    assert "if not data.startswith(b'MALW'):" in content, "parser.py appears to have been modified."

    with open(parser_path, 'rb') as f:
        actual = f.read()
    assert actual == EXPECTED_PARSER, "parser.py has been modified from its original contents."


def test_isolated_execution_reaches_original_vulnerable_line():
    parser_path = '/home/user/parser.py'
    minimal_bin_path = '/home/user/minimal_crash.bin'

    # Isolated mode prevents local module shadowing from changing struct's behavior.
    result = subprocess.run(
        ['python3', '-I', parser_path, minimal_bin_path],
        capture_output=True,
        text=True
    )

    assert result.returncode != 0, "Expected the unmodified parser to crash in isolated mode."
    expected_error = "struct.error: unpack requires a buffer of 8 bytes"
    assert expected_error in result.stderr, f"Expected stderr to contain '{expected_error}', but got:\n{result.stderr}"
    expected_frame = 'File "/home/user/parser.py", line 34, in parse_file'
    assert expected_frame in result.stderr, f"Crash did not occur at the original vulnerable line:\n{result.stderr}"
    assert "val = struct.unpack('<d', data[offset:offset+8])[0]" in result.stderr, f"Traceback did not identify the vulnerable unpack:\n{result.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
