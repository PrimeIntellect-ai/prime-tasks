#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import os
import secrets
import subprocess
import tempfile

SOURCE = "/home/user/detect.c"
EXECUTABLE = "/home/user/detect"
REPORT = "/home/user/audit_report.txt"
LOG = "/home/user/tx_logs.csv"
EXPECTED_REPORT = [
    "102,103,10,20",
    "104,105,80,90",
    "106,107,100,110",
    "108,109,120,130",
]
EXPECTED_FULL = [
    "100,101,50,60",
    "102,103,10,20",
    "104,105,80,90",
    "106,107,100,110",
    "108,109,120,130",
]


def run_program(path, limit, offset):
    result = subprocess.run(
        [path, str(limit), str(offset)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}; stderr: {result.stderr}"
    )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


# Preserve all original final-state assertions.
assert os.path.isfile(SOURCE), f"C source file {SOURCE} is missing."
assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
with open(EXECUTABLE, "rb") as f:
    assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled ELF executable."
assert os.path.isfile(REPORT), f"Audit report file {REPORT} is missing."
with open(REPORT, "r") as f:
    report_lines = [line.strip() for line in f if line.strip()]
assert report_lines == EXPECTED_REPORT, (
    f"Contents of {REPORT} do not match the expected output. Got: {report_lines}"
)

with open(LOG, "rb") as f:
    original_log = f.read()

fd, compiled_path = tempfile.mkstemp(prefix="detect-verified-", dir="/tmp")
os.close(fd)
os.unlink(compiled_path)

try:
    # Compile the submitted source using the exact toolchain required by the task.
    compile_result = subprocess.run(
        ["gcc", SOURCE, "-o", compiled_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        check=False,
    )
    assert compile_result.returncode == 0, (
        "detect.c did not compile with gcc: " + compile_result.stderr
    )

    # Both the delivered executable and a fresh build must answer the supplied query.
    for binary in (EXECUTABLE, compiled_path):
        assert run_program(binary, 5, 1) == EXPECTED_REPORT, (
            f"{binary} produced an incorrect result for limit=5 offset=1"
        )
        assert run_program(binary, 100, 0) == EXPECTED_FULL, (
            f"{binary} did not detect the complete supplied data set"
        )

    # Generate an unpredictable, disjoint collection of reverse-order lock pairs.
    # Expected answers are derived here rather than copied from an image-side oracle.
    rng = secrets.SystemRandom()
    transaction_ids = rng.sample(range(10000, 900000), 19)
    resource_ids = rng.sample(range(1000000, 1900000), 19)
    blocks = []
    expected = []
    for i in range(8):
        ta, tb = sorted(transaction_ids[2 * i:2 * i + 2])
        rx, ry = sorted(resource_ids[2 * i:2 * i + 2])
        blocks.append([(ta, rx), (tb, ry), (ta, ry), (tb, rx)])
        expected.append(f"{ta},{tb},{rx},{ry}")

    # Transactions with only one distinct resource are non-matching noise.
    for i in range(3):
        blocks.append([(transaction_ids[16 + i], resource_ids[16 + i])])

    rng.shuffle(blocks)
    events = [event for block in blocks for event in block]
    synthetic = "".join(
        f"{timestamp},{transaction},{resource}\n"
        for timestamp, (transaction, resource) in enumerate(events, 1)
    )
    with open(LOG, "w") as f:
        f.write(synthetic)

    expected.sort(key=lambda line: tuple(map(int, line.split(",")[:2])))
    page_cases = [(100, 0), (3, 0), (4, 2), (5, 1), (2, 7), (5, 20)]
    for binary in (EXECUTABLE, compiled_path):
        for limit, offset in page_cases:
            wanted = expected[offset:offset + limit]
            got = run_program(binary, limit, offset)
            assert got == wanted, (
                f"{binary} failed generated pagination limit={limit}, "
                f"offset={offset}. Expected {wanted}, got {got}"
            )
finally:
    with open(LOG, "wb") as f:
        f.write(original_log)
    try:
        os.unlink(compiled_path)
    except FileNotFoundError:
        pass
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
