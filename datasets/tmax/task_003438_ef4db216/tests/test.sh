#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import fcntl
import glob
import gzip
import os
import re
import secrets
import shutil
import signal
import stat
import subprocess
import threading
import time

ROTATOR = "/home/user/rotator.py"
ACTIVE_DIR = "/home/user/active_logs"
LOG_PATH = os.path.join(ACTIVE_DIR, "app.log")
ARCHIVE_DIR = "/home/user/archive"
TRUTH_PATH = "/home/user/.hidden/truth_count.txt"
TOTAL_EXPECTED = 1000
MAGIC = b"LOG_V1.0"
START_RE = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] (?:INFO|ERROR) ")
SPLIT_RE = re.compile(r"(?m)^(?=\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\])")


def reset_directory(path):
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    os.makedirs(path, mode=0o777)


def run_rotator(timeout=4):
    proc = subprocess.Popen(
        ["python3", ROTATOR],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        # A rotator implemented as a loop is permitted. Stop it after it has had
        # enough time to process the available records.
        os.killpg(proc.pid, signal.SIGTERM)
        try:
            stdout, stderr = proc.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            stdout, stderr = proc.communicate()
        return
    assert proc.returncode == 0, (
        f"rotator.py exited with status {proc.returncode}. "
        f"stdout={stdout.decode(errors='replace')!r}, "
        f"stderr={stderr.decode(errors='replace')!r}"
    )


def test_recovery_ratio_and_record_integrity():
    assert os.path.exists(ROTATOR), "Missing /home/user/rotator.py"
    mode = os.lstat(ROTATOR).st_mode
    assert stat.S_ISREG(mode), "rotator.py must be a regular file, not a link or special file"
    subprocess.run(
        ["python3", "-m", "py_compile", ROTATOR],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    reset_directory(ACTIVE_DIR)
    reset_directory(ARCHIVE_DIR)
    os.makedirs(os.path.dirname(TRUTH_PATH), exist_ok=True)
    if os.path.lexists(TRUTH_PATH):
        os.unlink(TRUTH_PATH)
    with open(TRUTH_PATH, "w", encoding="utf-8") as f:
        f.write(str(TOTAL_EXPECTED))

    # These unpredictable records are retained only in this test process and
    # are written by a live, locking writer while the submitted rotator runs.
    expected_records = []
    for i in range(TOTAL_EXPECTED):
        token = secrets.token_hex(12)
        level = "ERROR" if i % 3 == 0 else "INFO"
        record = f"[2026-09-11 12:34:56] {level} Record {i} token={token}\n"
        if level == "ERROR":
            record += f"    at com.example.Generated.run(Generated.java:{100 + i})\n"
            record += f"    caused-by-token: {token}\n"
        expected_records.append(record)

    started = threading.Event()
    writer_errors = []

    def writer():
        try:
            for i, record in enumerate(expected_records):
                with open(LOG_PATH, "a", encoding="utf-8") as f:
                    fcntl.flock(f, fcntl.LOCK_EX)
                    for line in record.splitlines(keepends=True):
                        f.write(line)
                    f.flush()
                    fcntl.flock(f, fcntl.LOCK_UN)
                if i == 119:
                    started.set()
                time.sleep(0.002)
        except BaseException as exc:
            writer_errors.append(exc)
            started.set()

    thread = threading.Thread(target=writer, daemon=True)
    thread.start()
    assert started.wait(10), "Controlled background writer did not start"
    assert not writer_errors, f"Controlled writer failed: {writer_errors!r}"

    # Rotate once during active appends, then once after the writer finishes so
    # a correct one-shot rotator as well as a looping rotator can recover data.
    run_rotator()
    thread.join(15)
    assert not thread.is_alive(), "Controlled background writer did not finish"
    assert not writer_errors, f"Controlled writer failed: {writer_errors!r}"
    run_rotator()

    assert os.path.exists(TRUTH_PATH), "Truth count file is missing."
    with open(TRUTH_PATH, "r", encoding="utf-8") as f:
        stored_total = int(f.read().strip())
    assert stored_total > 0, "Expected total records should be greater than 0."
    assert stored_total == TOTAL_EXPECTED, "The controlled truth count was modified"

    arc_files = glob.glob(os.path.join(ARCHIVE_DIR, "*.arc"))
    assert len(arc_files) > 0, "No .arc files found in /home/user/archive/"

    recovered = []
    header_errors = 0
    for arc in arc_files:
        assert stat.S_ISREG(os.lstat(arc).st_mode), f"Archive is not a regular file: {arc}"
        with open(arc, "rb") as f:
            data = f.read()
        if not data.startswith(MAGIC):
            header_errors += 1
            continue
        try:
            decompressed = gzip.decompress(data[8:]).decode("utf-8")
        except Exception as exc:
            raise AssertionError(f"Invalid gzip payload in {arc}: {exc}") from exc

        if not decompressed:
            continue
        assert decompressed.startswith("["), f"Non-record data precedes the first record in {arc}"
        records = [part for part in SPLIT_RE.split(decompressed) if part]
        for record in records:
            assert START_RE.match(record), f"Malformed archived record in {arc}: {record[:100]!r}"
        recovered.extend(records)

    assert header_errors == 0, (
        f"Found {header_errors} .arc files with incorrect or missing magic header "
        f"(expected LOG_V1.0)."
    )

    expected_set = set(expected_records)
    counts = collections.Counter(recovered)
    duplicates = [record for record, count in counts.items() if count > 1]
    unknown = [record for record in counts if record not in expected_set]
    assert not duplicates, f"Found {len(duplicates)} duplicated archived records"
    assert not unknown, f"Found {len(unknown)} fabricated or corrupted archived records"

    recovered_valid = sum(1 for record in expected_records if counts[record] == 1)
    recovery_ratio = recovered_valid / TOTAL_EXPECTED
    assert recovery_ratio >= 0.95, (
        f"Recovery ratio too low. Expected >= 0.95, got {recovery_ratio:.4f} "
        f"({recovered_valid} valid unique records out of {TOTAL_EXPECTED} generated)."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
