#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import struct
import base64
import math

SECRET_KEY_PATH = "/home/user/secret.key"
REPORT_BIN_PATH = "/home/user/diagnostic_report.bin"
REPORT_B64_PATH = "/home/user/report.b64"

def test_secret_key_exists_and_correct():
    assert os.path.isfile(SECRET_KEY_PATH), f"Missing secret key file at {SECRET_KEY_PATH}"

    with open(SECRET_KEY_PATH, "r") as f:
        content = f.read().strip()

    try:
        secret_val = float(content)
    except ValueError:
        assert False, f"Content of {SECRET_KEY_PATH} is not a valid float: {content}"

    assert math.isclose(secret_val, 3.14159, rel_tol=1e-5), \
        f"Secret key value is incorrect. Expected ~3.14159, got {secret_val}"

def test_diagnostic_report_bin():
    assert os.path.isfile(REPORT_BIN_PATH), f"Missing binary report file at {REPORT_BIN_PATH}"

    with open(REPORT_BIN_PATH, "rb") as f:
        data = f.read()

    assert len(data) == 20, \
        f"Binary report file must be exactly 20 bytes long (5 floats). Got {len(data)} bytes."

    floats = struct.unpack('5f', data)

    inputs = [10.5, 20.2, 15.0, 8.8, 42.0]
    secret = 3.14159
    expected = [(val * secret) / 7.0 for val in inputs]

    for i in range(5):
        assert math.isclose(floats[i], expected[i], rel_tol=1e-4), \
            f"Value mismatch at index {i}: got {floats[i]}, expected {expected[i]}"

def test_report_b64():
    assert os.path.isfile(REPORT_B64_PATH), f"Missing base64 report file at {REPORT_B64_PATH}"
    assert os.path.isfile(REPORT_BIN_PATH), f"Missing binary report file at {REPORT_BIN_PATH} to compare against"

    with open(REPORT_BIN_PATH, "rb") as f:
        bin_data = f.read()

    expected_b64 = base64.b64encode(bin_data).decode('utf-8')

    with open(REPORT_B64_PATH, "r") as f:
        actual_b64 = f.read().strip()

    assert actual_b64 == expected_b64, \
        "Base64 file content does not match the base64 encoding of the binary file."
TEST_EOF

verify_work() {
    local repo=/home/user/diag-collector
    local source="$repo/main.c"

    [ -f "$source" ] || return 1

    # Exercise the repaired functions with additional inputs and a different
    # serialization count, catching both integer truncation and <= count.
    cat << 'HARNESS_EOF' > /tmp/diag_source_harness.c
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define main diag_collector_program_main
#include "/home/user/diag-collector/main.c"
#undef main

int main(void) {
    float input[] = {-13.75f, 0.125f, 1.9f, 31.125f, 99.875f, -0.75f, 6.625f};
    float output[7] = {0};
    const float secret = 2.7182817f;

    process_data(input, 7, output, secret);
    for (int i = 0; i < 7; ++i) {
        float expected = (input[i] * secret) / 7.0f;
        float tolerance = 1e-6f * fmaxf(1.0f, fabsf(expected));
        if (fabsf(output[i] - expected) > tolerance)
            return 10 + i;
    }

    FILE *out = tmpfile();
    if (!out)
        return 30;
    serialize(output, 4, out);
    if (fflush(out) != 0 || ftell(out) != 4L * (long)sizeof(float))
        return 31;
    rewind(out);
    for (int i = 0; i < 4; ++i) {
        float value = 0.0f;
        if (fread(&value, sizeof(value), 1, out) != 1 || value != output[i])
            return 32;
    }
    fclose(out);
    return 0;
}
HARNESS_EOF

    gcc -std=c11 -Wall -Wextra /tmp/diag_source_harness.c -lm -o /tmp/diag_source_harness || return 1
    /tmp/diag_source_harness || return 1

    # Compile main.c independently and prove that the submitted source itself
    # generates the required report.
    gcc "$source" -o /tmp/diag_collector_source_build || return 1
    rm -f /home/user/diagnostic_report.bin
    timeout 5 /tmp/diag_collector_source_build || return 1
    python3 - << 'PY_EOF' || return 1
import math
import os
import struct
path = "/home/user/diagnostic_report.bin"
assert os.path.isfile(path)
data = open(path, "rb").read()
assert len(data) == 20
actual = struct.unpack("5f", data)
expected = [(x * 3.14159) / 7.0 for x in (10.5, 20.2, 15.0, 8.8, 42.0)]
assert all(math.isclose(a, e, rel_tol=1e-4) for a, e in zip(actual, expected))
PY_EOF

    # Require and execute an ELF binary that the agent compiled inside the
    # repository. Its run must recreate the report after it is removed.
    python3 - << 'PY_EOF' || return 1
import math
import os
import struct
import subprocess

repo = "/home/user/diag-collector"
report = "/home/user/diagnostic_report.bin"
expected = [(x * 3.14159) / 7.0 for x in (10.5, 20.2, 15.0, 8.8, 42.0)]

candidates = []
for root, dirs, files in os.walk(repo):
    dirs[:] = [d for d in dirs if d != ".git"]
    for name in files:
        path = os.path.join(root, name)
        try:
            if not os.path.isfile(path) or not os.access(path, os.X_OK):
                continue
            with open(path, "rb") as f:
                if f.read(4) == b"\x7fELF":
                    candidates.append(path)
        except OSError:
            pass

assert candidates, "No compiled ELF executable found in the repository"
valid = False
for executable in candidates:
    try:
        if os.path.exists(report):
            os.unlink(report)
        result = subprocess.run([executable], cwd=repo, timeout=5,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode != 0 or not os.path.isfile(report):
            continue
        data = open(report, "rb").read()
        if len(data) != 20:
            continue
        values = struct.unpack("5f", data)
        if all(math.isclose(a, e, rel_tol=1e-4)
               for a, e in zip(values, expected)):
            valid = True
            break
    except (OSError, subprocess.SubprocessError, struct.error):
        continue

assert valid, "No compiled repository executable generated the correct report"
PY_EOF
}

if verify_work && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
