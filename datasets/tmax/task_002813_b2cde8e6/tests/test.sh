#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import ast
import glob
import json
import os
import secrets
import shutil
import subprocess
import sys

OUTPUT_FILE = "/home/user/cleaned_logs.jsonl"
LOGS_DIR = "/home/user/logs"


def get_expected_records():
    log_files = glob.glob(os.path.join(LOGS_DIR, "etl_retry_*.log"))
    assert log_files, "Original log files are missing; cannot compute expected state."

    records_by_event = {}
    for filepath in log_files:
        with open(filepath, "rb") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                record = json.loads(line.decode("utf-8", errors="replace"))
                event_id = record["event_id"]
                retry_count = record["retry_count"]
                if (event_id not in records_by_event or
                        retry_count > records_by_event[event_id]["retry_count"]):
                    records_by_event[event_id] = record

    return sorted(records_by_event.values(),
                  key=lambda r: (r["timestamp"], r["event_id"]))


def read_and_validate_output(expected):
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a file."

    actual = []
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            pairs = json.loads(line, object_pairs_hook=lambda p: p)
            keys = [k for k, _ in pairs]
            assert keys == sorted(keys), f"JSON keys are not sorted alphabetically: {keys}"
            actual.append(dict(pairs))

    assert len(actual) == len(expected), (
        f"Expected {len(expected)} records after deduplication, but got {len(actual)}."
    )
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert got == want, (
            f"Record at index {i} does not match expected.\nActual: {got}\nExpected: {want}"
        )


def uses_parallel_api(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            tree = ast.parse(f.read(), filename=path)
    except (OSError, UnicodeError, SyntaxError):
        return False

    parallel_module_imported = False
    constructor_names = {
        "Pool", "ThreadPool", "Process", "ProcessPoolExecutor", "ThreadPoolExecutor"
    }
    imported_constructor_aliases = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "multiprocessing" or alias.name.startswith("multiprocessing.") \
                        or alias.name == "concurrent.futures":
                    parallel_module_imported = True
        elif isinstance(node, ast.ImportFrom):
            module = node.module or ""
            if module == "multiprocessing" or module.startswith("multiprocessing.") \
                    or module == "concurrent.futures":
                parallel_module_imported = True
                for alias in node.names:
                    if alias.name in constructor_names:
                        imported_constructor_aliases.add(alias.asname or alias.name)

    constructed = False
    dispatched = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Name):
            if func.id in constructor_names or func.id in imported_constructor_aliases:
                constructed = True
            if func.id in {"map", "starmap"}:
                dispatched = True
        elif isinstance(func, ast.Attribute):
            if func.attr in constructor_names:
                constructed = True
            if func.attr in {"map", "starmap", "imap", "imap_unordered", "submit", "start"}:
                dispatched = True

    return parallel_module_imported and constructed and dispatched


def write_challenge_logs(token):
    ids = [f"audit-{token}-{i}" for i in range(7)]
    records = [
        {"timestamp": "2024-02-03T09:00:03", "event_id": ids[0], "user_id": 201, "payload": "alpha", "retry_count": 0},
        {"timestamp": "2024-02-03T09:00:01", "event_id": ids[1], "user_id": 202, "payload": "bad PLACEHOLDER bytes", "retry_count": 1},
        {"timestamp": "2024-02-03T09:00:02", "event_id": ids[2], "user_id": 203, "payload": "old", "retry_count": 0},
        {"timestamp": "2024-02-03T09:00:02", "event_id": ids[2], "user_id": 203, "payload": "new", "retry_count": 8},
        {"timestamp": "2024-02-03T09:00:04", "event_id": ids[3], "user_id": 204, "payload": "delta", "retry_count": 2},
        {"timestamp": "2024-02-03T09:00:00", "event_id": ids[4], "user_id": 205, "payload": "first", "retry_count": 3},
        {"timestamp": "2024-02-03T09:00:04", "event_id": ids[5], "user_id": 206, "payload": "tie", "retry_count": 0},
        {"timestamp": "2024-02-03T09:00:05", "event_id": ids[6], "user_id": 207, "payload": "last", "retry_count": 0},
        {"timestamp": "2024-02-03T09:00:03", "event_id": ids[0], "user_id": 201, "payload": "alpha-retry", "retry_count": 5},
        {"timestamp": "2024-02-03T09:00:01", "event_id": ids[1], "user_id": 202, "payload": "bad PLACEHOLDER bytes", "retry_count": 7},
    ]
    distributions = [[0, 1, 2], [3, 4], [5, 6, 8], [7, 9, 2]]

    for old in glob.glob(os.path.join(LOGS_DIR, "etl_retry_*.log")):
        os.remove(old)
    for i, indexes in enumerate(distributions):
        path = os.path.join(LOGS_DIR, f"etl_retry_{i}.log")
        with open(path, "wb") as f:
            for index in indexes:
                raw = json.dumps(records[index], sort_keys=True).encode("utf-8")
                raw = raw.replace(b"PLACEHOLDER", b"\xff\xfe")
                f.write(raw + b"\n")


def main():
    # Preserve all original behavioral assertions before changing the inputs.
    original_expected = get_expected_records()
    read_and_validate_output(original_expected)

    candidates = []
    for path in glob.glob("/home/user/**/*.py", recursive=True):
        if os.path.isfile(path) and not os.path.islink(path) and uses_parallel_api(path):
            candidates.append(path)
    assert candidates, (
        "No Python script under /home/user uses multiprocessing or concurrent.futures "
        "with a parallel dispatch operation."
    )

    backup_dir = "/tmp/original_etl_logs"
    shutil.rmtree(backup_dir, ignore_errors=True)
    os.makedirs(backup_dir)
    original_logs = glob.glob(os.path.join(LOGS_DIR, "etl_retry_*.log"))
    for path in original_logs:
        shutil.copy2(path, backup_dir)
    output_backup = None
    if os.path.isfile(OUTPUT_FILE):
        output_backup = "/tmp/original_cleaned_logs.jsonl"
        shutil.copy2(OUTPUT_FILE, output_backup)

    token = secrets.token_hex(8)
    errors = []
    passed = False
    try:
        for script in candidates:
            write_challenge_logs(token)
            if os.path.lexists(OUTPUT_FILE):
                os.remove(OUTPUT_FILE)
            try:
                result = subprocess.run(
                    [sys.executable, script], cwd="/home/user",
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, timeout=30
                )
                if result.returncode != 0:
                    errors.append(f"{script}: exited {result.returncode}: {result.stderr[-500:]}")
                    continue
                challenge_expected = get_expected_records()
                read_and_validate_output(challenge_expected)
                passed = True
                break
            except Exception as exc:
                errors.append(f"{script}: {exc}")
        assert passed, "No parallel-processing Python script produced the required output: " + " | ".join(errors)
    finally:
        for path in glob.glob(os.path.join(LOGS_DIR, "etl_retry_*.log")):
            os.remove(path)
        for path in glob.glob(os.path.join(backup_dir, "etl_retry_*.log")):
            shutil.copy2(path, LOGS_DIR)
        if output_backup and os.path.exists(output_backup):
            shutil.copy2(output_backup, OUTPUT_FILE)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
