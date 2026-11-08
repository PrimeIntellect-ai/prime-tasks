#!/bin/bash
mkdir -p /logs/verifier
reward=0
PROJECT=/home/user/log_organizer
BINARY="$PROJECT/target/release/log_organizer"

cat <<'PY' > /tmp/prepare_inputs.py
import gzip
import json
import os
import secrets
import shutil

raw = "/home/user/raw_logs"
organized = "/home/user/organized_logs"
dynamic = os.path.join(raw, "verifier_dynamic")
shutil.rmtree(dynamic, ignore_errors=True)
os.makedirs(dynamic, exist_ok=True)
shutil.rmtree(organized, ignore_errors=True)
os.makedirs(organized, exist_ok=True)

base = 1800000000 + secrets.randbelow(1000000)
apps = [f"verify_{secrets.token_hex(5)}" for _ in range(4)]
for i in range(24):
    subdir = os.path.join(dynamic, f"batch_{i % 5}")
    os.makedirs(subdir, exist_ok=True)
    app = apps[i % len(apps)]
    timestamp = base + ((i * 7919) % 100003)
    filename = f"dynamic_{i}_{secrets.token_hex(3)}.gz"
    path = os.path.join(subdir, filename)
    with gzip.open(path, "wt", encoding="utf-8") as out:
        out.write(json.dumps({"app_id": app, "timestamp": timestamp}) + "\n")
        out.write("verification payload\n" * 8)
PY

cat <<'PY' > /tmp/check_binary.py
import os
import sys

path = sys.argv[1]
assert os.path.isfile(path), f"release binary missing: {path}"
assert not os.path.islink(path), f"release binary must not be a symlink: {path}"
assert os.access(path, os.X_OK), f"release binary is not executable: {path}"
with open(path, "rb") as f:
    assert f.read(4) == b"\x7fELF", "release artifact is not an ELF executable"
PY

cat <<'PY' > /tmp/run_with_manifest_lock.py
import fcntl
import os
import subprocess
import sys
import time

binary = sys.argv[1]
organized = "/home/user/organized_logs"
manifest = os.path.join(organized, "manifest.log")
os.makedirs(organized, exist_ok=True)

fd = os.open(manifest, os.O_RDWR | os.O_CREAT, 0o666)
proc = None
try:
    # Hold both Linux flock and POSIX record locks. A correct implementation using
    # either common OS-level locking mechanism must wait before appending.
    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    fcntl.lockf(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    proc = subprocess.Popen([binary], cwd=os.path.dirname(binary),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True)
    time.sleep(1.25)
    if proc.poll() is not None:
        out, err = proc.communicate()
        raise AssertionError(
            "program exited while manifest was exclusively locked; "
            "OS-level append locking was not honored\nstdout:\n%s\nstderr:\n%s" % (out, err)
        )
finally:
    try:
        fcntl.lockf(fd, fcntl.LOCK_UN)
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)

try:
    out, err = proc.communicate(timeout=60)
except subprocess.TimeoutExpired:
    proc.kill()
    out, err = proc.communicate()
    raise AssertionError("program did not finish after manifest lock release")
if proc.returncode != 0:
    raise AssertionError(
        "release binary failed with status %d\nstdout:\n%s\nstderr:\n%s"
        % (proc.returncode, out, err)
    )
PY

cat <<'PY' > /tmp/test_final_state.py
import os
import gzip
import json
import re
import pytest

RAW_LOGS_DIR = "/home/user/raw_logs"
ORGANIZED_LOGS_DIR = "/home/user/organized_logs"
MANIFEST_FILE = os.path.join(ORGANIZED_LOGS_DIR, "manifest.log")
PROJECT_DIR = "/home/user/log_organizer"


def test_rust_implementation_requirements():
    cargo_toml = os.path.join(PROJECT_DIR, "Cargo.toml")
    assert os.path.isfile(cargo_toml), "Cargo.toml is missing from the required Rust project"
    with open(cargo_toml, "r", encoding="utf-8") as f:
        cargo = f.read().lower()
    assert re.search(r'^\s*name\s*=\s*["\']log_organizer["\']', cargo, re.MULTILINE), \
        "Cargo package must be named log_organizer"

    rust_files = []
    source_parts = []
    src_dir = os.path.join(PROJECT_DIR, "src")
    for root, _, files in os.walk(src_dir):
        for name in files:
            if name.endswith(".rs"):
                path = os.path.join(root, name)
                rust_files.append(path)
                with open(path, "r", encoding="utf-8") as f:
                    source_parts.append(f.read())
    assert rust_files, "Rust source files are missing"
    source = "\n".join(source_parts)
    lower = source.lower()

    assert ("gzdecoder" in lower or "multigzdecoder" in lower), \
        "Rust source does not use a streaming gzip decoder"
    assert any(token in lower for token in ("read_line", "read_until", ".lines()")), \
        "Rust source does not stream/read the gzip metadata line"
    assert any(token in lower for token in
               ("par_iter", "par_bridge", "into_par_iter", "thread::spawn", "thread::scope", "rayon::")), \
        "Rust source does not implement concurrent archive processing"
    assert any(token in lower for token in
               ("lock_exclusive", "try_lock_exclusive", "fd_lock", "flock", "fcntl")), \
        "Rust source does not implement OS-level manifest locking"


@pytest.fixture(scope="module")
def expected_state():
    """Derive the required output from every current raw gzip file."""
    hard_links = []
    latest_by_app = {}
    manifest_lines = []

    for root, _, files in os.walk(RAW_LOGS_DIR):
        for file in files:
            if file.endswith(".gz"):
                src_path = os.path.join(root, file)
                try:
                    with gzip.open(src_path, 'rt', encoding='utf-8') as f:
                        first_line = f.readline().strip()
                        metadata = json.loads(first_line)
                except Exception as e:
                    pytest.fail(f"Could not read raw log {src_path}: {e}")

                app_id = metadata.get("app_id")
                timestamp = metadata.get("timestamp")
                if not app_id or not timestamp:
                    continue

                dest_filename = f"{timestamp}_{file}"
                dest_path = os.path.join(ORGANIZED_LOGS_DIR, app_id, dest_filename)
                hard_links.append({
                    "src_path": src_path,
                    "dest_path": dest_path,
                    "app_id": app_id,
                    "timestamp": timestamp,
                    "original_filename": file,
                })
                manifest_lines.append(f"LINKED {file} TO {app_id}")
                if app_id not in latest_by_app or timestamp > latest_by_app[app_id]["timestamp"]:
                    latest_by_app[app_id] = {"timestamp": timestamp, "filename": dest_filename}

    return {
        "hard_links": hard_links,
        "latest_symlinks": latest_by_app,
        "manifest_lines": manifest_lines,
    }


def test_hard_links_created(expected_state):
    """Test that all expected hard links are created and inodes match."""
    for link_info in expected_state["hard_links"]:
        src_path = link_info["src_path"]
        dest_path = link_info["dest_path"]
        assert os.path.exists(dest_path), f"Expected hard link missing: {dest_path}"
        src_inode = os.stat(src_path).st_ino
        dest_inode = os.stat(dest_path).st_ino
        assert src_inode == dest_inode, \
            f"Inode mismatch for {dest_path}. Expected it to be a hard link to {src_path}."


def test_symlinks_for_latest_logs(expected_state):
    """Test that symlinks resolve to the expected latest hard links."""
    for app_id, latest_info in expected_state["latest_symlinks"].items():
        symlink_path = os.path.join(ORGANIZED_LOGS_DIR, app_id, "latest.gz")
        assert os.path.islink(symlink_path), f"Expected symlink missing or not a symlink: {symlink_path}"
        target = os.readlink(symlink_path)
        expected_target_ending = latest_info["filename"]
        assert target.endswith(expected_target_ending), \
            f"Symlink {symlink_path} points to {target}, expected it to point to {expected_target_ending}"

        expected_path = os.path.join(ORGANIZED_LOGS_DIR, app_id, expected_target_ending)
        assert os.path.realpath(symlink_path) == os.path.realpath(expected_path), \
            f"Symlink {symlink_path} does not resolve to the expected hard-link path {expected_path}"
        assert os.path.samefile(symlink_path, expected_path), \
            f"Symlink {symlink_path} does not resolve to the expected hard link"


def test_manifest_file_contents(expected_state):
    """Test that the manifest file contains exactly the expected lines, unbroken."""
    assert os.path.exists(MANIFEST_FILE), f"Manifest file missing: {MANIFEST_FILE}"
    with open(MANIFEST_FILE, 'r', encoding='utf-8') as f:
        actual_lines = f.read().splitlines()
    expected_lines = expected_state["manifest_lines"]
    assert len(actual_lines) == len(expected_lines), \
        f"Manifest has {len(actual_lines)} lines, expected {len(expected_lines)}."
    for line in set(expected_lines):
        expected_count = expected_lines.count(line)
        actual_count = actual_lines.count(line)
        assert actual_count == expected_count, \
            f"Manifest line '{line}' appears {actual_count} times, expected {expected_count}."
PY

if [ -f "$PROJECT/Cargo.toml" ] \
   && cargo build --release --manifest-path "$PROJECT/Cargo.toml" \
   && python3 /tmp/check_binary.py "$BINARY" \
   && python3 /tmp/prepare_inputs.py \
   && python3 /tmp/run_with_manifest_lock.py "$BINARY" \
   && python3 -m pytest /tmp/test_final_state.py -x --tb=short; then
    reward=1
fi

echo "$reward" > /logs/verifier/reward.txt
