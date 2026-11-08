#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/atomic_hook
cat <<'HOOK_EOF' > /tmp/atomic_hook/sitecustomize.py
import builtins
import io
import os

_atomic_log = os.environ.get("VERIFIER_ATOMIC_LOG")
_open_log = os.environ.get("VERIFIER_OPEN_LOG")
_orig_open = builtins.open
_orig_io_open = io.open
_orig_rename = os.rename
_orig_replace = os.replace

def _record_open(path):
    if not _open_log:
        return
    try:
        st = os.stat(path, follow_symlinks=True)
        resolved = os.path.abspath(os.fspath(path))
        with _orig_open(_open_log, "a", encoding="utf-8") as log:
            log.write(f"{st.st_dev}\t{st.st_ino}\t{resolved}\n")
    except Exception:
        pass

def checked_open(file, mode="r", *args, **kwargs):
    result = _orig_open(file, mode, *args, **kwargs)
    if isinstance(mode, str) and "r" in mode and not any(flag in mode for flag in "wax+"):
        _record_open(file)
    return result

def checked_io_open(file, mode="r", *args, **kwargs):
    result = _orig_io_open(file, mode, *args, **kwargs)
    if isinstance(mode, str) and "r" in mode and not any(flag in mode for flag in "wax+"):
        _record_open(file)
    return result

def _record_atomic(src, dst):
    if not _atomic_log:
        return
    try:
        src = os.path.abspath(os.fspath(src))
        dst = os.path.abspath(os.fspath(dst))
        with _orig_open(_atomic_log, "a", encoding="utf-8") as log:
            log.write(f"{src}\t{dst}\n")
    except Exception:
        pass

def checked_rename(src, dst, *args, **kwargs):
    result = _orig_rename(src, dst, *args, **kwargs)
    _record_atomic(src, dst)
    return result

def checked_replace(src, dst, *args, **kwargs):
    result = _orig_replace(src, dst, *args, **kwargs)
    _record_atomic(src, dst)
    return result

builtins.open = checked_open
io.open = checked_io_open
os.rename = checked_rename
os.replace = checked_replace
HOOK_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import shutil
import subprocess
import uuid

EXTRACTED = "/home/user/extracted_backup"
SCRIPT = "/home/user/process.py"
CSV_DIR = "/home/user/processed_csv"
ATOMIC_LOG = "/tmp/verifier_atomic.log"
OPEN_LOG = "/tmp/verifier_open.log"

ORIGINAL_RECORDS = [
    {"id": 5, "name": "Alice", "timestamp": "2023-01-01"},
    {"id": 12, "name": "Bob", "timestamp": "2023-01-02"},
    {"id": 8, "name": "Charlie", "timestamp": "2023-01-03"},
    {"id": 1, "name": "Dave", "timestamp": "2023-01-04"},
    {"id": 15, "name": "Eve", "timestamp": "2023-01-05"},
    {"id": 3, "name": "Frank", "timestamp": "2023-01-06"},
    {"id": 9, "name": "Grace", "timestamp": "2023-01-07"},
]

def reset_output_and_logs():
    shutil.rmtree(CSV_DIR, ignore_errors=True)
    os.makedirs(CSV_DIR)
    for path in (ATOMIC_LOG, OPEN_LOG):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

def run_process():
    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp/atomic_hook" + (":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["VERIFIER_ATOMIC_LOG"] = ATOMIC_LOG
    env["VERIFIER_OPEN_LOG"] = OPEN_LOG
    result = subprocess.run(
        ["python3", SCRIPT], env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=12
    )
    assert result.returncode == 0, f"process.py failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"

def expected_chunks(records):
    unique = {}
    for record in records:
        key = (record["id"], record["name"], record["timestamp"])
        unique[key] = record
    ordered = sorted(unique.values(), key=lambda r: r["id"])
    return [ordered[i:i + 3] for i in range(0, len(ordered), 3)]

def assert_csv_output(records):
    chunks = expected_chunks(records)
    expected_names = [f"chunk_{i}.csv" for i in range(len(chunks))]
    actual_names = sorted(
        name for name in os.listdir(CSV_DIR)
        if name.startswith("chunk_") and name.endswith(".csv")
    )
    assert actual_names == expected_names, f"Expected chunk files {expected_names}, got {actual_names}"
    for index, chunk in enumerate(chunks):
        path = os.path.join(CSV_DIR, f"chunk_{index}.csv")
        with open(path, newline="", encoding="utf-8") as handle:
            rows = list(csv.reader(handle))
        expected = [["id", "name", "timestamp"]] + [
            [str(r["id"]), r["name"], r["timestamp"]] for r in chunk
        ]
        assert rows == expected, f"Incorrect content in {path}: got {rows}, expected {expected}"

def assert_atomic_writes(chunk_count):
    assert os.path.isfile(ATOMIC_LOG), "No successful atomic rename/replace operation was observed"
    operations = []
    with open(ATOMIC_LOG, encoding="utf-8") as handle:
        for line in handle:
            src, dst = line.rstrip("\n").split("\t", 1)
            operations.append((src, dst))
    for index in range(chunk_count):
        final = os.path.abspath(os.path.join(CSV_DIR, f"chunk_{index}.csv"))
        matching = [(src, dst) for src, dst in operations if dst == final]
        assert matching, f"chunk_{index}.csv was not installed with os.rename/os.replace/shutil.move"
        assert any(src != final and os.path.dirname(src) == os.path.dirname(final)
                   for src, _ in matching), (
            f"chunk_{index}.csv was not renamed from a temporary file in the same directory"
        )

def test_complete_backup_processing():
    # Preserve the original existence and source-level atomic-operation assertions.
    assert os.path.isdir(EXTRACTED), f"{EXTRACTED}/ directory does not exist. Did you extract the archive?"
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    with open(SCRIPT, "r", encoding="utf-8") as handle:
        content = handle.read()
    assert any(func in content for func in ["os.rename", "os.replace", "shutil.move"]), (
        "The script does not appear to use os.rename, os.replace, or shutil.move for atomic writes."
    )

    # Verify that extraction retained the supplied links rather than using a dummy directory.
    file1 = os.path.join(EXTRACTED, "dirA", "file1.json")
    hardlink = os.path.join(EXTRACTED, "dirC", "file1_hardlink.json")
    loop_a = os.path.join(EXTRACTED, "dirA", "link_to_B")
    loop_b = os.path.join(EXTRACTED, "dirB", "link_to_A")
    assert os.path.isfile(file1) and os.path.isfile(hardlink), "Extracted JSON files are missing"
    assert os.stat(file1).st_ino == os.stat(hardlink).st_ino, "The archive hard link was not preserved"
    assert os.path.islink(loop_a) and os.path.islink(loop_b), "The archive symlink loop was not preserved"

    # Remove any pre-fabricated output, execute the submitted artifact, and retain the
    # original fixed-dataset content and no-extra-chunks checks.
    reset_output_and_logs()
    run_process()
    assert_csv_output(ORIGINAL_RECORDS)
    assert_atomic_writes(3)

    # Add an unpredictable fixture containing duplicate records, malformed JSON,
    # a hard link, a file symlink, and directory loops, then execute again.
    case = os.path.join(EXTRACTED, "verifier_" + uuid.uuid4().hex)
    os.makedirs(os.path.join(case, "nested"))
    rng = random.SystemRandom()
    ids = rng.sample(range(1000, 9000), 6)
    dynamic = [
        {"id": ids[i], "name": "name_" + uuid.uuid4().hex,
         "timestamp": f"2042-07-{i + 10:02d}T12:34:56Z"}
        for i in range(6)
    ]
    primary = os.path.join(case, "primary.json")
    secondary = os.path.join(case, "nested", "secondary.json")
    with open(primary, "w", encoding="utf-8") as handle:
        json.dump(dynamic[:4], handle)
    with open(secondary, "w", encoding="utf-8") as handle:
        json.dump([dynamic[0], dynamic[4], dynamic[5]], handle)
    os.link(primary, os.path.join(case, "primary_hardlink.json"))
    os.symlink("primary.json", os.path.join(case, "primary_symlink.json"))
    with open(os.path.join(case, "broken.json"), "w", encoding="utf-8") as handle:
        handle.write("{ this is deliberately invalid JSON")
    os.symlink("..", os.path.join(case, "nested", "loop_to_parent"))
    os.symlink(".", os.path.join(case, "self_loop"))

    reset_output_and_logs()
    run_process()
    all_records = ORIGINAL_RECORDS + dynamic
    assert_csv_output(all_records)
    assert_atomic_writes(len(expected_chunks(all_records)))

    # A normal Python JSON reader must not process the same inode through the
    # primary path, its hard link, and its symlink more than once.
    inode = os.stat(primary).st_ino
    device = os.stat(primary).st_dev
    seen = 0
    if os.path.isfile(OPEN_LOG):
        with open(OPEN_LOG, encoding="utf-8") as handle:
            for line in handle:
                fields = line.rstrip("\n").split("\t", 2)
                if len(fields) == 3 and int(fields[0]) == device and int(fields[1]) == inode:
                    seen += 1
    assert seen <= 1, f"The same physical JSON file was opened {seen} times through links"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
