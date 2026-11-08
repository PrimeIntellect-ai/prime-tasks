#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/verifier_hooks

cat << 'PY_EOF' > /tmp/prepare_verification.py
import hashlib
import json
import os
import secrets

raw_dir = "/home/user/raw_logs"
token = secrets.token_hex(12)
challenge_name = f"verifier_{token}.log"
challenge_path = os.path.join(raw_dir, challenge_name)
ids = [secrets.randbelow(800000) + 100000 for _ in range(3)]
detail = secrets.token_hex(24)
content = (
    f"=== START TRANSACTION {ids[0]} ===\n"
    "Timestamp: 2026-01-02 03:04:05\n"
    "Status: SUCCESS\n"
    "Details:\n"
    f"  verifier success {detail}\n"
    f"=== END TRANSACTION {ids[0]} ===\n"
    f"=== START TRANSACTION {ids[1]} ===\n"
    "Timestamp: 2026-01-02 03:05:06\n"
    "Status: FAILED\n"
    "Details:\n"
    f"  verifier failure {detail}\n"
    "    preserved indentation\n"
    f"=== END TRANSACTION {ids[1]} ===\n"
    f"=== START TRANSACTION {ids[2]} ===\n"
    "Timestamp: 2026-01-02 03:06:07\n"
    "Status: FAILED\n"
    "Details:\n"
    "  second dynamic failure\n"
    f"=== END TRANSACTION {ids[2]} ===\n"
).encode("utf-8")
with open(challenge_path, "wb") as f:
    f.write(content)

snapshot = {}
for name in sorted(os.listdir(raw_dir)):
    if name.endswith(".log"):
        path = os.path.join(raw_dir, name)
        with open(path, "rb") as f:
            snapshot[name] = hashlib.sha256(f.read()).hexdigest()
with open("/tmp/raw_snapshot.json", "w", encoding="utf-8") as f:
    json.dump(snapshot, f)
with open("/tmp/challenge_name", "w", encoding="utf-8") as f:
    f.write(challenge_name)
PY_EOF
python3 /tmp/prepare_verification.py

rm -rf /home/user/processed_logs
rm -f /tmp/atomic_trace.jsonl /tmp/process_run_status

cat << 'PY_EOF' > /tmp/verifier_hooks/sitecustomize.py
import json
import os
import sys

_OUT = os.path.normpath("/home/user/processed_logs")
_TRACE_FD = os.open("/tmp/atomic_trace.jsonl", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
_original_rename = os.rename
_original_replace = os.replace

def _norm(path, dir_fd=None):
    try:
        path = os.fsdecode(path)
        if os.path.isabs(path):
            return os.path.normpath(path)
        base = os.getcwd()
        if dir_fd is not None:
            try:
                base = os.readlink(f"/proc/self/fd/{dir_fd}")
            except OSError:
                pass
        return os.path.normpath(os.path.join(base, path))
    except Exception:
        return repr(path)

def _relevant(path):
    return path == _OUT or path.startswith(_OUT + os.sep)

def _emit(record):
    try:
        os.write(_TRACE_FD, (json.dumps(record, sort_keys=True) + "\n").encode("utf-8"))
    except Exception:
        pass

def _source_is_open(source):
    try:
        for fd in os.listdir("/proc/self/fd"):
            try:
                target = os.readlink("/proc/self/fd/" + fd)
            except OSError:
                continue
            if target.endswith(" (deleted)"):
                target = target[:-10]
            if _norm(target) == source:
                return True
    except Exception:
        pass
    return False

def _rename(kind, original, src, dst, *, src_dir_fd=None, dst_dir_fd=None):
    source = _norm(src, src_dir_fd)
    destination = _norm(dst, dst_dir_fd)
    existed = os.path.isfile(source)
    source_open = _source_is_open(source)
    result = original(src, dst, src_dir_fd=src_dir_fd, dst_dir_fd=dst_dir_fd)
    if _relevant(source) or _relevant(destination):
        _emit({"event": "rename", "kind": kind, "src": source, "dst": destination,
               "source_existed": existed, "source_open": source_open})
    return result

def rename(src, dst, *, src_dir_fd=None, dst_dir_fd=None):
    return _rename("rename", _original_rename, src, dst,
                   src_dir_fd=src_dir_fd, dst_dir_fd=dst_dir_fd)

def replace(src, dst, *, src_dir_fd=None, dst_dir_fd=None):
    return _rename("replace", _original_replace, src, dst,
                   src_dir_fd=src_dir_fd, dst_dir_fd=dst_dir_fd)

os.rename = rename
os.replace = replace

def _audit(event, args):
    if event != "open" or not args:
        return
    path = _norm(args[0])
    if not _relevant(path):
        return
    mode = args[1] if len(args) > 1 else None
    flags = args[2] if len(args) > 2 else 0
    writable = False
    if isinstance(mode, str):
        writable = any(c in mode for c in "wax+")
    if isinstance(flags, int):
        writable = writable or bool(flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND))
    _emit({"event": "open", "path": path, "mode": mode, "flags": flags,
           "writable": writable})

sys.addaudithook(_audit)
PY_EOF

set +e
PYTHONPATH=/tmp/verifier_hooks python3 /home/user/process_logs.py
run_status=$?
set -e
echo "$run_status" > /tmp/process_run_status

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import stat
import pytest

RAW_DIR = "/home/user/raw_logs"
OUT_DIR = "/home/user/processed_logs"
MANIFEST_PATH = os.path.join(OUT_DIR, "manifest.json")
SCRIPT_PATH = "/home/user/process_logs.py"
TRACE_PATH = "/tmp/atomic_trace.jsonl"

def get_file_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256.update(chunk)
    return sha256.hexdigest()

def extract_transactions(content):
    transactions = []
    current_tx = []
    in_tx = False
    for line in content.splitlines(keepends=True):
        if line.startswith("=== START TRANSACTION"):
            in_tx = True
            current_tx = [line]
        elif line.startswith("=== END TRANSACTION"):
            if in_tx:
                current_tx.append(line)
                transactions.append("".join(current_tx))
                in_tx = False
        elif in_tx:
            current_tx.append(line)
    return transactions

def expected_failed_bytes(content):
    transactions = []
    current = []
    in_tx = False
    for line in content.splitlines(keepends=True):
        if line.startswith(b"=== START TRANSACTION"):
            in_tx = True
            current = [line]
        elif line.startswith(b"=== END TRANSACTION"):
            if in_tx:
                current.append(line)
                if any(part.rstrip(b"\r\n") == b"Status: FAILED" for part in current):
                    transactions.append(b"".join(current))
                in_tx = False
                current = []
        elif in_tx:
            current.append(line)
    return b"".join(transactions)

def load_trace():
    assert os.path.exists(TRACE_PATH), "Atomic-write trace was not produced."
    records = []
    with open(TRACE_PATH, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                records.append(json.loads(line))
    return records

def raw_log_names():
    return sorted(name for name in os.listdir(RAW_DIR) if name.endswith(".log"))

def test_script_exists_and_was_executed():
    assert os.path.lexists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert not os.path.islink(SCRIPT_PATH), "process_logs.py must be a real script, not a symlink."
    mode = os.stat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), "process_logs.py is not a regular file."
    with open("/tmp/process_run_status", "r", encoding="utf-8") as f:
        status = int(f.read().strip())
    assert status == 0, f"Executing process_logs.py returned status {status}."

def test_processed_logs_dir_exists():
    assert os.path.exists(OUT_DIR), f"Output directory {OUT_DIR} does not exist."
    assert os.path.isdir(OUT_DIR), f"{OUT_DIR} is not a directory."

def test_no_tmp_files():
    assert os.path.exists(OUT_DIR), f"Output directory {OUT_DIR} does not exist."
    for fname in os.listdir(OUT_DIR):
        assert not fname.endswith(".tmp"), f"Temporary file {fname} found in {OUT_DIR}."

def test_node1_log_content():
    processed_node1 = os.path.join(OUT_DIR, "node1.log")
    assert os.path.exists(processed_node1), f"Processed file {processed_node1} does not exist."
    with open(processed_node1, "r") as f:
        content = f.read()
    transactions = extract_transactions(content)
    assert len(transactions) == 1, f"Expected exactly 1 transaction in node1.log, found {len(transactions)}."
    assert "=== START TRANSACTION 102 ===" in transactions[0], "Transaction 102 is missing in node1.log."
    assert "Status: FAILED" in transactions[0], "Transaction 102 should have Status: FAILED."
    assert "=== START TRANSACTION 101 ===" not in content, "Transaction 101 (SUCCESS) should not be in node1.log."
    assert "=== START TRANSACTION 103 ===" not in content, "Transaction 103 (SUCCESS) should not be in node1.log."

def test_node2_log_content():
    processed_node2 = os.path.join(OUT_DIR, "node2.log")
    assert os.path.exists(processed_node2), f"Processed file {processed_node2} does not exist."
    with open(processed_node2, "r") as f:
        content = f.read()
    transactions = extract_transactions(content)
    assert len(transactions) == 2, f"Expected exactly 2 transactions in node2.log, found {len(transactions)}."
    tx_ids = []
    for tx in transactions:
        if "=== START TRANSACTION 201 ===" in tx:
            tx_ids.append(201)
        elif "=== START TRANSACTION 202 ===" in tx:
            tx_ids.append(202)
    assert 201 in tx_ids, "Transaction 201 is missing in node2.log."
    assert 202 in tx_ids, "Transaction 202 is missing in node2.log."

def test_every_processed_log_is_exact_failed_record_bytes():
    expected_names = raw_log_names()
    actual_logs = sorted(name for name in os.listdir(OUT_DIR) if name.endswith(".log"))
    assert actual_logs == expected_names, "Processed .log filenames do not exactly match the raw .log filenames."
    for name in expected_names:
        with open(os.path.join(RAW_DIR, name), "rb") as f:
            expected = expected_failed_bytes(f.read())
        with open(os.path.join(OUT_DIR, name), "rb") as f:
            actual = f.read()
        assert actual == expected, f"{name} does not preserve the failed transaction records byte-for-byte."

def test_raw_logs_were_not_modified():
    with open("/tmp/raw_snapshot.json", "r", encoding="utf-8") as f:
        snapshot = json.load(f)
    assert sorted(snapshot) == raw_log_names(), "Raw log files were added, removed, or renamed by the script."
    for name, digest in snapshot.items():
        assert get_file_sha256(os.path.join(RAW_DIR, name)) == digest, f"Raw input {name} was modified."

def test_atomic_temp_write_and_rename_protocol():
    records = load_trace()
    names = raw_log_names()
    rename_indices = []
    for name in names:
        final_path = os.path.join(OUT_DIR, name)
        tmp_path = final_path + ".tmp"
        matches = [(i, record) for i, record in enumerate(records)
                   if record.get("event") == "rename"
                   and record.get("src") == tmp_path
                   and record.get("dst") == final_path]
        assert matches, f"No atomic rename from {name}.tmp to {name} was observed."
        index, event = matches[-1]
        assert event.get("source_existed"), f"Temporary file {name}.tmp did not exist at rename time."
        assert not event.get("source_open"), f"Temporary file {name}.tmp was still open when renamed."
        assert any(r.get("event") == "open" and r.get("path") == tmp_path and r.get("writable")
                   for r in records[:index]), f"{name}.tmp was not opened for writing before its rename."
        rename_indices.append(index)
    for record in records:
        if record.get("event") == "open" and record.get("writable"):
            path = record.get("path", "")
            assert not (path.startswith(OUT_DIR + os.sep) and path.endswith(".log")), \
                f"Final processed log was opened for direct writing instead of being atomically installed: {path}"
    manifest_writes = [i for i, record in enumerate(records)
                       if record.get("event") == "open"
                       and record.get("path") == MANIFEST_PATH
                       and record.get("writable")]
    assert manifest_writes, "Manifest was not generated by the executed script."
    assert min(manifest_writes) > max(rename_indices), "Manifest was written before all processed logs were atomically renamed."

def test_manifest_exists_and_valid():
    assert os.path.exists(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} does not exist."
    with open(MANIFEST_PATH, "r") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Manifest file {MANIFEST_PATH} is not valid JSON.")
    assert isinstance(manifest, dict), "Manifest JSON should be a dictionary."
    expected_files = ["node1.log", "node2.log"]
    for fname in expected_files:
        assert fname in manifest, f"File {fname} is missing from the manifest."
        filepath = os.path.join(OUT_DIR, fname)
        assert os.path.exists(filepath), f"File {fname} listed in manifest does not exist in {OUT_DIR}."
        actual_hash = get_file_sha256(filepath)
        assert manifest[fname] == actual_hash, f"SHA256 hash mismatch for {fname}. Expected {actual_hash}, got {manifest[fname]}."
    all_expected = raw_log_names()
    assert sorted(manifest) == all_expected, "Manifest keys must exactly match all processed log filenames."
    for fname in all_expected:
        digest = manifest[fname]
        assert isinstance(digest, str) and len(digest) == 64
        assert all(c in "0123456789abcdef" for c in digest), f"Invalid SHA256 digest for {fname}."
        assert digest == get_file_sha256(os.path.join(OUT_DIR, fname)), f"SHA256 hash mismatch for {fname}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
