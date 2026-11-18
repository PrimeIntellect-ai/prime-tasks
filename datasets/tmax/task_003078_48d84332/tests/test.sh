#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import os
import re
import secrets
import stat
import subprocess
from decimal import Decimal

SOURCE = "/home/user/process.c"
BINARY = "/tmp/process_verified"
INPUT = "/home/user/input.csv"
OUTPUT = "/home/user/output.csv"

# Preserve the original verifier's assertion on the agent-generated fixture output.
assert os.path.exists(OUTPUT), f"Missing required output file: {OUTPUT}"
assert os.path.isfile(OUTPUT), f"Expected {OUTPUT} to be a file, but it is not."

expected_content = (
    "1700000000,LocátionB,15.50\n"
    "1700000060,LocátionB,15.50\n"
    "1700000120,Tést✓,20.00\n"
    "1700000180,New Data,25.00\n"
)
with open(OUTPUT, "r", encoding="utf-8") as f:
    actual_content = f.read()
actual_lines = [line.strip() for line in actual_content.strip().split("\n")]
expected_lines = [line.strip() for line in expected_content.strip().split("\n")]
assert len(actual_lines) == len(expected_lines), \
    f"Expected {len(expected_lines)} lines in {OUTPUT}, but found {len(actual_lines)}."
for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
    assert actual == expected, \
        f"Line {i+1} in {OUTPUT} does not match.\nExpected: {expected}\nActual:   {actual}"

# Require and freshly compile the requested C source.
assert os.path.exists(SOURCE), f"Missing required C source: {SOURCE}"
assert stat.S_ISREG(os.stat(SOURCE).st_mode), f"Expected {SOURCE} to be a regular file"
compile_result = subprocess.run(
    ["gcc", "-std=c11", "-O2", SOURCE, "-o", BINARY],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    timeout=20,
)
assert compile_result.returncode == 0, \
    f"Failed to compile {SOURCE}:\n{compile_result.stdout}{compile_result.stderr}"
assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Compiler did not produce an executable"

escape_re = re.compile(r"\\u([0-9a-fA-F]{4})")

def normalize_message(message):
    return escape_re.sub(lambda m: chr(int(m.group(1), 16)), message)

def djb2(message):
    value = 5381
    for byte in message.encode("utf-8"):
        value = ((value * 33) + byte) & 0xffffffffffffffff
    return value

def oracle(csv_text):
    valid = []
    seen = {}
    for raw_line in csv_text.splitlines():
        if not raw_line:
            continue
        timestamp_text, escaped_message, reading = raw_line.split(",", 2)
        timestamp = int(timestamp_text)
        message = normalize_message(escaped_message)
        h = djb2(message)
        bucket = seen.setdefault(h, [])
        if message in bucket:
            continue
        bucket.append(message)
        valid.append((timestamp, message, reading))

    assert valid, "Verifier fixture unexpectedly has no valid rows"
    t0 = valid[0][0]
    last_timestamp = valid[-1][0]
    result = []
    previous = None
    index = 0
    bucket_start = t0
    while bucket_start <= last_timestamp:
        bucket_end = bucket_start + 60
        latest = None
        while index < len(valid) and valid[index][0] < bucket_end:
            if valid[index][0] >= bucket_start:
                latest = valid[index]
            index += 1
        if latest is not None:
            previous = latest
        assert previous is not None
        result.append(
            f"{bucket_start},{previous[1]},{format(Decimal(previous[2]), '.2f')}\n"
        )
        bucket_start += 60
    return "".join(result)

def run_case(name, csv_text, literal_expected=None):
    with open(INPUT, "w", encoding="utf-8", newline="") as f:
        f.write(csv_text)
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run(
        [BINARY],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=8,
    )
    assert result.returncode == 0, \
        f"Program failed on {name} (exit {result.returncode}):\n{result.stdout}{result.stderr}"
    assert os.path.exists(OUTPUT), f"Program did not create {OUTPUT} for {name}"
    assert os.path.isfile(OUTPUT), f"Program created a non-file output for {name}"
    with open(OUTPUT, "r", encoding="utf-8") as f:
        actual = f.read()
    expected = oracle(csv_text)
    assert actual == expected, \
        f"Incorrect output for {name}.\nExpected:\n{expected!r}\nActual:\n{actual!r}"
    if literal_expected is not None:
        assert actual == literal_expected

original_input = (
    "1700000000,Sensor\\u0020A,10.00\n"
    "1700000015,Sensor\\u0020A,12.00\n"
    "1700000030,Loc\\u00e1tionB,15.50\n"
    "1700000059,Loc\\u00e1tionB,16.00\n"
    "1700000150,T\\u00e9st\\u2713,20.00\n"
    "1700000160,Sensor A,99.99\n"
    "1700000200,New\\u0020Data,25.00\n"
)
run_case("original fixture", original_input, expected_content)

nonce = secrets.token_hex(6)
base = 2000000000 + secrets.randbelow(500000)
# "Ab" and "BA" deliberately collide under djb2 but are distinct messages.
case_one = (
    f"{base},{nonce}\\u0020A,1.10\n"
    f"{base+10},Ab,2.20\n"
    f"{base+20},BA,3.30\n"
    f"{base+59},{nonce} A,99.99\n"
    f"{base+60},Caf\\u00E9,4.40\n"
    f"{base+61},Café,88.88\n"
    f"{base+185},Mark\\u2713,5.50\n"
    f"{base+240},Ab,77.77\n"
)
run_case("randomized normalization, collision, global dedup and gaps", case_one)

nonce2 = secrets.token_hex(5)
base2 = 2100000000 + secrets.randbelow(500000)
case_two = (
    f"{base2},\\u03A9-{nonce2},10.00\n"
    f"{base2+58},tail-{nonce2},11.25\n"
    f"{base2+60},\\u4F60\\u597D-{nonce2},12.50\n"
    f"{base2+119},Ω-{nonce2},90.00\n"
    f"{base2+180},end-{nonce2},13.75\n"
)
run_case("bucket boundaries and multibyte BMP escapes", case_two)
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
