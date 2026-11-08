#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import shutil
import stat
import subprocess
import time
import uuid

SCRIPT_PATH = "/home/user/compile_docs.py"
OUTPUT_PATH = "/home/user/compiled_docs.md"
LOCK_PATH = "/home/user/docs.lock"
RAW_DIR = "/home/user/raw_notes"

EXPECTED_MARKDOWN = """## Initial Setup
*2023-10-01*

Set up the core repository.
Added initial README.

## API v2 Deployment
*2023-10-04*

Deployed the new v2 endpoints to production.
No downtime observed.

## Database Migration
*2023-10-05*

Migrated the users table to PostgreSQL.
Updated the connection strings."""


def normalized(text):
    return "\n".join(line.rstrip() for line in text.strip().splitlines())


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_script_contains_required_functions():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    assert "fcntl.flock" in content, "Script does not use fcntl.flock as required."
    assert "os.replace" in content or "shutil.move" in content, \
        "Script does not use os.replace or shutil.move for atomic updates."


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_PATH), \
        f"Compiled documentation {OUTPUT_PATH} does not exist. Did you run the script?"


def test_output_file_content():
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    assert normalized(content) == normalized(EXPECTED_MARKDOWN), \
        f"Contents of {OUTPUT_PATH} do not match the expected format and sorting."


def test_script_processes_changed_inputs_and_uses_lock_and_atomic_replace():
    token = uuid.uuid4().hex
    raw_backup = f"{RAW_DIR}.verifier-backup-{token}"
    output_backup = f"{OUTPUT_PATH}.verifier-backup-{token}"
    proc = None
    lock_file = None
    lock_held = False

    records_a = [
        (f"Late {token}", "2024-12-31", f"late line one {token}\nlate line two"),
        (f"Tie First {token}", "2024-05-06", f"first tied body {token}"),
        (f"Tie Second {token}", "2024-05-06", f"second tied body {token}\ncontinued"),
    ]
    records_b = [
        (f"Earliest {token}", "2022-01-02", f"earliest body {token}\nsecond line"),
    ]

    def raw_text(records):
        return "".join(
            f"Title: {title}\nDate: {date}\nBody:\n{body}\n===END===\n"
            for title, date, body in records
        )

    sorted_records = [records_b[0], records_a[1], records_a[2], records_a[0]]
    expected = "\n\n".join(
        f"## {title}\n*{date}*\n\n{body}"
        for title, date, body in sorted_records
    )

    try:
        os.rename(RAW_DIR, raw_backup)
        os.mkdir(RAW_DIR)
        with open(os.path.join(RAW_DIR, "alpha.txt"), "w", encoding="utf-8") as f:
            f.write(raw_text(records_a))
        with open(os.path.join(RAW_DIR, "beta.txt"), "w", encoding="utf-8") as f:
            f.write(raw_text(records_b))
        with open(os.path.join(RAW_DIR, "ignored.md"), "w", encoding="utf-8") as f:
            f.write(f"Title: Must Be Ignored {token}\nDate: 1900-01-01\nBody:\nignored\n===END===\n")

        os.rename(OUTPUT_PATH, output_backup)
        sentinel = f"unchanged while locked {token}"
        with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
            f.write(sentinel)
        old_inode = os.stat(OUTPUT_PATH).st_ino

        lock_file = open(LOCK_PATH, "a+", encoding="utf-8")
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        lock_held = True

        proc = subprocess.Popen(
            [SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        time.sleep(0.5)

        assert proc.poll() is None, \
            "Script did not block while another process held /home/user/docs.lock."
        with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
            assert f.read() == sentinel, \
                "Script modified compiled_docs.md without first obtaining the dedicated lock."

        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        lock_held = False
        stdout, stderr = proc.communicate(timeout=10)
        assert proc.returncode == 0, \
            f"Executing compile_docs.py failed. stdout={stdout!r}, stderr={stderr!r}"

        assert os.path.isfile(OUTPUT_PATH), "Script did not create compiled_docs.md."
        assert os.stat(OUTPUT_PATH).st_ino != old_inode, \
            "compiled_docs.md was updated in place instead of being atomically replaced."
        with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
            actual = f.read()
        assert normalized(actual) == normalized(expected), \
            "Script did not correctly parse, stably sort, and format changed input files."
    finally:
        if lock_file is not None:
            if lock_held:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
            lock_file.close()
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        if os.path.isdir(RAW_DIR):
            shutil.rmtree(RAW_DIR)
        if os.path.exists(raw_backup):
            os.rename(raw_backup, RAW_DIR)
        if os.path.lexists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        if os.path.lexists(output_backup):
            os.rename(output_backup, OUTPUT_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
