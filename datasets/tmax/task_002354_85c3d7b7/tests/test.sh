#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import base64
import ctypes
import json
import math
import os
import secrets
import stat
import subprocess

HOME = "/home/user"
BUILD = os.path.join(HOME, "build.sh")
LIB = os.path.join(HOME, "fast_math.so")
SCRIPT = os.path.join(HOME, "aggregate_metrics.py")
METRICS = os.path.join(HOME, "metrics.json")
OUTPUT = os.path.join(HOME, "output.txt")


def expected_result(record):
    score = (record["cpu"] * 1.5) + (record["memory"] * 2.0) / math.log(record["uptime"] + 2)
    checksum = math.sin(score) + math.cos(score)
    return score, checksum


def run_and_check(records):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    subprocess.run(
        ["python3", SCRIPT], cwd=HOME, check=True, timeout=20,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert os.path.isfile(OUTPUT), f"File {OUTPUT} was not generated."

    with open(OUTPUT, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(records), (
        f"Expected exactly {len(records)} lines in {OUTPUT}, found {len(lines)}."
    )

    for i, (line, record) in enumerate(zip(lines, records), 1):
        try:
            decoded = base64.b64decode(line, validate=True).decode("utf-8")
            data = json.loads(decoded)
        except Exception as exc:
            raise AssertionError(
                f"Failed to decode and parse line {i} as base64-encoded JSON: {exc}"
            ) from exc

        assert data.get("server") == record["id"], (
            f"Expected server id {record['id']} in line {i}."
        )
        assert "score" in data, f"'score' missing in line {i} JSON."
        assert "checksum" in data, f"'checksum' missing in line {i} JSON."

        score, checksum = expected_result(record)
        assert math.isclose(data["score"], score, rel_tol=1e-5), (
            f"Score for {record['id']} is {data['score']}, expected {score}."
        )
        assert math.isclose(data["checksum"], checksum, rel_tol=1e-5), (
            f"Checksum for {record['id']} is {data['checksum']}, expected {checksum}."
        )


assert os.path.isfile(BUILD), f"File {BUILD} is missing."
assert os.stat(BUILD).st_mode & stat.S_IXUSR, f"File {BUILD} is not executable."
with open(BUILD, "r", encoding="utf-8") as f:
    build_content = f.read()
assert "-lm" in build_content, "The build.sh script does not contain the '-lm' linker flag."
assert os.path.isfile(SCRIPT), f"File {SCRIPT} is missing."
assert os.path.isfile(METRICS), f"File {METRICS} is missing."

# A stale or pre-supplied library cannot satisfy this check: build.sh must create it.
if os.path.exists(LIB):
    os.remove(LIB)
subprocess.run(
    ["./build.sh"], cwd=HOME, check=True, timeout=20,
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
)
assert os.path.isfile(LIB), "build.sh did not create /home/user/fast_math.so."
with open(LIB, "rb") as f:
    assert f.read(4) == b"\x7fELF", "fast_math.so is not an ELF shared library."

# Confirm that -lm was an effective linker input, rather than text in a comment.
dynamic = subprocess.run(
    ["readelf", "-d", LIB], check=True, timeout=10,
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
).stdout
assert "libm.so" in dynamic, "fast_math.so is not dynamically linked against libm."

# Load and exercise the newly built library directly.
lib = ctypes.CDLL(LIB)
compute_checksum = lib.compute_checksum
compute_checksum.argtypes = [ctypes.c_double]
compute_checksum.restype = ctypes.c_double
for value in (0.125, -3.75, 17.2, secrets.SystemRandom().uniform(-100.0, 100.0)):
    actual = compute_checksum(value)
    expected = math.sin(value) + math.cos(value)
    assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), (
        f"compute_checksum({value}) returned {actual}, expected {expected}."
    )

with open(METRICS, "rb") as f:
    original_metrics_bytes = f.read()
original_records = json.loads(original_metrics_bytes.decode("utf-8"))
assert isinstance(original_records, list), "metrics.json must contain a JSON array."
assert len(original_records) == 2, "The original metrics fixture must contain exactly two records."

try:
    # Execute against and validate the actual metrics file, rather than hardcoded records.
    run_and_check(original_records)

    # Exercise the implementation on verifier-generated records to reject fabricated output.
    rng = secrets.SystemRandom()
    challenge_records = [
        {
            "id": "verify-" + secrets.token_hex(6),
            "cpu": rng.uniform(1.0, 99.0),
            "memory": rng.uniform(1.0, 99.0),
            "uptime": rng.randint(1, 365),
        }
        for _ in range(5)
    ]
    with open(METRICS, "w", encoding="utf-8") as f:
        json.dump(challenge_records, f)
    run_and_check(challenge_records)
finally:
    # Restore the task input and, when possible, leave output.txt for that input.
    with open(METRICS, "wb") as f:
        f.write(original_metrics_bytes)
    subprocess.run(
        ["python3", SCRIPT], cwd=HOME, timeout=20,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
