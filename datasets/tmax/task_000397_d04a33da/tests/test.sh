#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import struct
import subprocess

SOURCE = "/home/user/recover.c"
BINARY = "/tmp/recover_submission"
WAL = "/home/user/wal.dat"
LOG = "/home/user/app.log"
REPORT = "/home/user/recovery_report.txt"


def run_recovery():
    if os.path.exists(REPORT):
        os.remove(REPORT)
    result = subprocess.run(
        [BINARY],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"recover program exited with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_report_lines():
    assert os.path.isfile(REPORT), f"Expected report file not found at {REPORT}"
    with open(REPORT, "r") as f:
        content = f.read().strip()
    lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert len(lines) == 2, f"Expected exactly 2 lines in the report, got {len(lines)}"
    return lines


def derive_expected(wal_path, log_path):
    with open(log_path, "r") as f:
        log_text = f.read()
    processed = re.findall(r"Processing record ID\s+(\d+)", log_text)
    assert processed, "Test log does not identify a crashing record"
    corrupt_id = int(processed[-1])

    with open(wal_path, "rb") as f:
        raw = f.read()
    magic, count = struct.unpack_from("<4sI", raw, 0)
    assert magic == b"WAL1"

    recovered = []
    precision_ids = []
    offset = 8
    for _ in range(count):
        record_id, original_val, stored_val, _ = struct.unpack_from("<Idf32s", raw, offset)
        offset += 48
        if record_id == corrupt_id:
            continue
        recovered.append(record_id)
        if abs(original_val - stored_val) > 0.01:
            precision_ids.append(record_id)

    assert len(precision_ids) == 1
    return [
        "Recovered IDs: " + ",".join(str(x) for x in recovered),
        f"Precision Loss ID: {precision_ids[0]}",
    ]


def write_dynamic_fixture():
    rng = random.SystemRandom()
    valid_ids = rng.sample(range(100, 10000), 4)
    precision_id = rng.choice(valid_ids)
    corrupt_index = rng.randrange(5)

    ordered_ids = valid_ids[:]
    ordered_ids.insert(corrupt_index, 4)

    with open(WAL, "wb") as f:
        f.write(struct.pack("<4sI", b"WAL1", len(ordered_ids)))
        for i, record_id in enumerate(ordered_ids):
            if record_id == 4:
                original = 99.9
                stored = 99.9
                data = b"X" * 32
            elif record_id == precision_id:
                original = 123456789.123 + 8 * i
                stored = original
                data = (f"loss-{record_id}").encode()
            else:
                original = float(20 + 2 * i)
                stored = original
                data = (f"data-{record_id}").encode()
            f.write(struct.pack("<Idf32s", record_id, original, stored, data))

    with open(LOG, "w") as f:
        f.write("[INFO] Container started.\n")
        f.write("[INFO] Opening WAL file...\n")
        f.write(f"[INFO] Found {len(ordered_ids)} records in WAL.\n")
        for record_id in ordered_ids[:corrupt_index + 1]:
            f.write(f"[INFO] Processing record ID {record_id}\n")
        f.write("[ERROR] Segmentation fault (core dumped)\n")


def test_recovery_program_and_report():
    # Preserve the original source-existence assertion.
    assert os.path.isfile(SOURCE), f"Expected C source file not found at {SOURCE}"

    compile_result = subprocess.run(
        ["gcc", "-std=c11", SOURCE, "-o", BINARY, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f"recover.c did not compile with gcc\nstdout:\n{compile_result.stdout}"
        f"\nstderr:\n{compile_result.stderr}"
    )

    # Execute against the original WAL and preserve the original exact checks.
    run_recovery()
    actual_lines = read_report_lines()
    expected_lines = [
        "Recovered IDs: 1,2,3,5",
        "Precision Loss ID: 2",
    ]
    assert actual_lines[0] == expected_lines[0], (
        f"Expected first line to be '{expected_lines[0]}', but got '{actual_lines[0]}'"
    )
    assert actual_lines[1] == expected_lines[1], (
        f"Expected second line to be '{expected_lines[1]}', but got '{actual_lines[1]}'"
    )

    wal_backup = WAL + ".verifier_backup"
    log_backup = LOG + ".verifier_backup"
    shutil.copyfile(WAL, wal_backup)
    shutil.copyfile(LOG, log_backup)
    try:
        # A fresh randomized WAL ensures the submitted program actually parses records.
        write_dynamic_fixture()
        expected_dynamic = derive_expected(WAL, LOG)
        run_recovery()
        assert read_report_lines() == expected_dynamic
    finally:
        shutil.move(wal_backup, WAL)
        shutil.move(log_backup, LOG)

    # Leave and verify the requested report for the original supplied data.
    run_recovery()
    assert read_report_lines() == expected_lines
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
