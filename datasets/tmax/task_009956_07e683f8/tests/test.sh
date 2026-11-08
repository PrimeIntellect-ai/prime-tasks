#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import shutil
import subprocess
import uuid
from datetime import datetime, timedelta
from pathlib import Path

CSV_PATH = Path("/home/user/failed_backups.csv")
ARCHIVE_ROOT = Path("/home/user/archive_mounts")

EXPECTED_ORIGINAL_ROWS = [
    ["timestamp", "absolute_file_path"],
    ["2023-09-15 01:50:33", "/home/user/archive_mounts/server_beta/app/logs/old/archive_2023.log"],
    ["2023-10-01 02:05:12", "/home/user/archive_mounts/server_alpha/var/log/backup.log"],
    ["2023-11-20 03:15:22", "/home/user/archive_mounts/server_gamma/sys/system.log"],
]


def read_csv_rows():
    with CSV_PATH.open("r", newline="") as f:
        return list(csv.reader(f))


def test_failed_backups_csv_exists():
    csv_path = "/home/user/failed_backups.csv"
    assert os.path.isfile(csv_path), f"The file {csv_path} does not exist."


def test_failed_backups_csv_content():
    csv_path = "/home/user/failed_backups.csv"
    assert os.path.isfile(csv_path), f"The file {csv_path} does not exist."

    expected_rows = EXPECTED_ORIGINAL_ROWS

    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i} mismatch. Expected {expected}, but got {actual}."


def find_python_scripts():
    home = Path("/home/user")
    scripts = []
    for path in home.rglob("*"):
        if not path.is_file() or path == CSV_PATH:
            continue
        try:
            path.relative_to(ARCHIVE_ROOT)
            continue
        except ValueError:
            pass

        is_python = path.suffix.lower() == ".py"
        if not is_python:
            try:
                first_line = path.open("rb").readline(256).lower()
                is_python = first_line.startswith(b"#!") and b"python" in first_line
            except OSError:
                is_python = False
        if is_python:
            scripts.append(path)
    return sorted(scripts)


def write_file(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def create_random_corpus():
    shutil.rmtree(ARCHIVE_ROOT, ignore_errors=True)
    ARCHIVE_ROOT.mkdir(parents=True)

    token = uuid.uuid4().hex
    start = datetime(2031, 1, 1) + timedelta(seconds=secrets.randbelow(200000000))
    older = start.replace(microsecond=0)
    newer = older + timedelta(seconds=1 + secrets.randbelow(500000))
    fake = newer + timedelta(seconds=1 + secrets.randbelow(500000))
    old_ts = older.strftime("%Y-%m-%d %H:%M:%S")
    new_ts = newer.strftime("%Y-%m-%d %H:%M:%S")
    fake_ts = fake.strftime("%Y-%m-%d %H:%M:%S")

    path_old = ARCHIVE_ROOT / f"node_{uuid.uuid4().hex}" / "a" / "b" / "old.log"
    path_tie_a = ARCHIVE_ROOT / f"node_{uuid.uuid4().hex}" / "deep" / "tie_a.log"
    path_tie_b = ARCHIVE_ROOT / f"node_{uuid.uuid4().hex}" / "deeper" / "x" / "tie_b.log"
    ignored_txt = ARCHIVE_ROOT / f"node_{uuid.uuid4().hex}" / "ignored.txt"

    write_file(path_old, f"""[{fake_ts}] INFO - Ordinary record {token}
FATAL - Backup job failed: this is only continuation text
  [{fake_ts}] FATAL - Backup job failed: indented continuation
[{old_ts}] FATAL - Backup job failed: randomized failure {token}
Traceback follows
  detail {token}
[{new_ts}] ERROR - Backup job failed: wrong severity
""")

    write_file(path_tie_a, f"""[{old_ts}] INFO - Backup job started
continued output
[{new_ts}] FATAL - Backup job failed: randomized tie A {token}
more output
[{fake_ts}] FATAL - Routine message mentioning Backup job failed
""")

    write_file(path_tie_b, f"""[{new_ts}] FATAL - Backup job failed: randomized tie B {token}
line one
line two
[{fake_ts}] WARN - Backup job failed: wrong severity
""")

    write_file(ignored_txt, f"[{old_ts}] FATAL - Backup job failed: non-log file {token}\n")

    data_rows = [
        [old_ts, str(path_old.resolve())],
        [new_ts, str(path_tie_a.resolve())],
        [new_ts, str(path_tie_b.resolve())],
    ]
    data_rows.sort(key=lambda row: (row[0], row[1]))
    return [["timestamp", "absolute_file_path"], *data_rows]


def test_python_script_recursively_parses_arbitrary_multiline_logs():
    scripts = find_python_scripts()
    assert scripts, "No Python script was found under /home/user."

    backup_root = Path(f"/tmp/archive_mounts_original_{uuid.uuid4().hex}")
    csv_existed = CSV_PATH.exists()
    csv_original = CSV_PATH.read_bytes() if csv_existed else None
    errors = []

    ARCHIVE_ROOT.rename(backup_root)
    try:
        expected_rows = create_random_corpus()
        for script in scripts:
            create_random_corpus_rows = expected_rows
            # Recreate the same corpus if a previous candidate altered it.
            # For the first candidate it is already present.
            if not ARCHIVE_ROOT.exists():
                errors.append(f"{script}: archive root was removed")
                break

            try:
                if CSV_PATH.exists():
                    CSV_PATH.unlink()
                result = subprocess.run(
                    ["python3", str(script)],
                    cwd="/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=15,
                )
                if result.returncode != 0:
                    errors.append(f"{script}: exited {result.returncode}: {result.stderr[-500:]}")
                    continue
                if not CSV_PATH.is_file():
                    errors.append(f"{script}: did not create {CSV_PATH}")
                    continue
                actual_rows = read_csv_rows()
                if actual_rows == create_random_corpus_rows:
                    return
                errors.append(f"{script}: produced {actual_rows!r}, expected {create_random_corpus_rows!r}")
            except (OSError, subprocess.TimeoutExpired, UnicodeError) as exc:
                errors.append(f"{script}: {exc}")

        raise AssertionError("No discovered Python script passed the randomized execution test. " + " | ".join(errors))
    finally:
        shutil.rmtree(ARCHIVE_ROOT, ignore_errors=True)
        backup_root.rename(ARCHIVE_ROOT)
        if csv_existed:
            CSV_PATH.write_bytes(csv_original)
        elif CSV_PATH.exists():
            CSV_PATH.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
