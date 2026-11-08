#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PREFLIGHT_EOF' > /tmp/verify_artifacts.py
import hashlib
import math
import os
import re
import subprocess

GENERATOR = "/home/user/generate.sh"
BINARY = "/home/user/suspicious"
INPUT = "/home/user/input.txt"
FLAG = "/home/user/flag.txt"
TRACE = "/tmp/suspicious-final.strace"


def remove(path):
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.digest()


assert os.path.isfile(GENERATOR) and not os.path.islink(GENERATOR), "generate.sh must be a regular file"
assert os.access(GENERATOR, os.X_OK), "generate.sh is not executable"
assert os.path.isfile(BINARY) and not os.path.islink(BINARY), "suspicious must be a regular file"
assert os.access(BINARY, os.X_OK), "suspicious is not executable"
with open(BINARY, "rb") as f:
    assert f.read(4) == b"\x7fELF", "suspicious is not an ELF executable"

binary_hash = digest(BINARY)
remove(FLAG)
remove(INPUT)

result = subprocess.run([GENERATOR], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                        text=True, timeout=10)
assert result.returncode == 0, f"generate.sh failed:\n{result.stdout}"
assert not os.path.exists(FLAG), "generate.sh created the flag instead of letting suspicious trigger the payload"
assert digest(BINARY) == binary_hash, "generate.sh modified suspicious"
assert os.path.isfile(INPUT) and not os.path.islink(INPUT), "generate.sh did not create a regular input.txt"

with open(INPUT, "rb") as f:
    generated_input = f.read()
assert generated_input, "input.txt is empty"
text = generated_input.decode("utf-8")
lines = text.splitlines()
assert lines, "input.txt contains no coordinate lines"
for line in lines:
    assert line.startswith("DATA:"), f"Malformed coordinate line: {line!r}"
    value_text = line[5:].strip()
    assert value_text, f"Missing coordinate value: {line!r}"
    try:
        value = float(value_text)
    except ValueError:
        raise AssertionError(f"Invalid coordinate value: {line!r}")
    assert math.isfinite(value), f"Coordinate must be finite: {line!r}"

# Preserve the agent-generated input while checking that the executable still
# exhibits its real parser and rejects a non-target sum.
with open(INPUT, "wb") as f:
    f.write(b"BROKEN:1.0\n")
remove(FLAG)
bad = subprocess.run([BINARY], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                     text=True, timeout=10)
assert "Format error" in bad.stdout, "suspicious did not reject malformed input"
assert not os.path.exists(FLAG), "Malformed input unexpectedly produced the payload"

with open(INPUT, "wb") as f:
    f.write(b"DATA:0\n")
remove(FLAG)
wrong = subprocess.run([BINARY], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       text=True, timeout=10)
assert "Sum is incorrect." in wrong.stdout, "suspicious did not reject a valid non-target sum"
assert "Format error" not in wrong.stdout, "suspicious failed to parse a valid DATA line"
assert not os.path.exists(FLAG), "A non-target sum unexpectedly produced the payload"

with open(INPUT, "wb") as f:
    f.write(generated_input)
remove(FLAG)
remove(TRACE)
final = subprocess.run([
    "strace", "-f", "-qq", "-e", "trace=openat,write", "-o", TRACE, BINARY
], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=10)
assert final.returncode == 0, f"suspicious failed on generated input:\n{final.stdout}"
assert "Format error" not in final.stdout, "Generated input caused a Format error"
assert digest(BINARY) == binary_hash, "suspicious was modified during verification"
assert os.path.isfile(TRACE), "No execution trace was produced"
with open(TRACE, "r", errors="replace") as f:
    trace = f.read()
flag_open = re.search(r'openat\([^\n]*"/home/user/flag\.txt"[^\n]*O_WRONLY[^\n]*O_CREAT', trace)
assert flag_open, "The executed suspicious binary did not create /home/user/flag.txt"
PREFLIGHT_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_flag_file_exists_and_correct():
    flag_path = "/home/user/flag.txt"

    # Check if the file exists
    assert os.path.isfile(flag_path), f"The flag file {flag_path} does not exist. Did you successfully trigger the payload?"

    # Check the content of the file
    with open(flag_path, "r") as f:
        content = f.read().strip()

    expected_content = "PAYLOAD_UNLOCKED_77492"
    assert content == expected_content, f"The content of {flag_path} is incorrect. Expected '{expected_content}', but got '{content}'."
TEST_EOF

if python3 /tmp/verify_artifacts.py 2>&1 && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
