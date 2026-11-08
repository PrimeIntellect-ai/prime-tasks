#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import json
import os
import secrets
import shutil
import struct
import subprocess
import tarfile
import time

LEGACY_PARSER = "/app/legacy_parser"
AGENT_BINARY = "/home/user/fast_organizer"
AGENT_SOURCE = "/home/user/fast_organizer.cpp"
INCOMING_DIR = "/home/user/incoming"
BACKUP_DIR = "/home/user/dataset_backup"
ARCHIVE_DIR = os.path.join(BACKUP_DIR, "archive")
INCREMENTAL_DIR = os.path.join(BACKUP_DIR, "incremental")
COMPILED_DATA = os.path.join(BACKUP_DIR, "compiled_data.json")


def stop_agents(proc=None):
    if proc is not None and proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)
    subprocess.run(["pkill", "-TERM", "-x", "fast_organizer"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.2)
    subprocess.run(["pkill", "-KILL", "-x", "fast_organizer"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)


def clear_dir(path):
    os.makedirs(path, exist_ok=True)
    for name in os.listdir(path):
        target = os.path.join(path, name)
        if os.path.isdir(target) and not os.path.islink(target):
            shutil.rmtree(target)
        else:
            os.remove(target)


def reset_outputs():
    stop_agents()
    clear_dir(INCOMING_DIR)
    clear_dir(ARCHIVE_DIR)
    clear_dir(INCREMENTAL_DIR)
    if os.path.exists(COMPILED_DATA):
        os.remove(COMPILED_DATA)


def make_wal(path, count):
    records = []
    base_ts = secrets.randbelow(4_000_000_000_000) + 1_000_000_000
    nonce = secrets.token_hex(10)
    with open(path, "wb") as f:
        f.write(b"WAL1")
        for i in range(count):
            ts = base_ts + i * (1 + secrets.randbelow(4))
            payload = f"{nonce}_{i}_{secrets.token_hex(3 + (i % 13))}"
            encoded = payload.encode("ascii")
            f.write(struct.pack("<IQI", 0xDEADBEEF, ts, len(encoded)))
            f.write(encoded)
            records.append({"ts": ts, "data": payload})
    return records


def get_json_records(filepath):
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    records = []
    decoder = json.JSONDecoder()
    idx = 0
    while idx < len(content):
        while idx < len(content) and content[idx].isspace():
            idx += 1
        if idx == len(content):
            break
        obj, idx = decoder.raw_decode(content, idx)
        if isinstance(obj, list):
            records.extend(obj)
        else:
            records.append(obj)
    return records


def wait_for(path, timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.exists(path):
            return
        time.sleep(0.05)
    raise AssertionError(f"Timed out waiting for {path}")


def tar_state():
    state = {}
    for name in os.listdir(INCREMENTAL_DIR):
        path = os.path.join(INCREMENTAL_DIR, name)
        if os.path.isfile(path):
            state[path] = os.stat(path).st_mtime_ns
    return state


def wait_for_new_tar(previous, required_name, forbidden_name=None, timeout=20):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        current = tar_state()
        candidates = [p for p, stamp in current.items()
                      if p not in previous or previous[p] != stamp]
        candidates.sort(key=lambda p: os.stat(p).st_mtime_ns, reverse=True)
        for path in candidates:
            try:
                with tarfile.open(path, "r:gz") as tf:
                    members = {os.path.basename(m.name.rstrip("/")) for m in tf.getmembers()}
                if required_name in members and (forbidden_name is None or forbidden_name not in members):
                    return path
            except (tarfile.TarError, OSError) as exc:
                last_error = exc
        time.sleep(0.1)
    raise AssertionError(f"No new incremental gzip tar contained {required_name}; last error: {last_error}")


def test_artifacts_and_required_interfaces():
    assert os.path.isfile(AGENT_SOURCE), f"Missing C++ source at {AGENT_SOURCE}"
    assert os.path.isfile(AGENT_BINARY), f"Missing agent binary at {AGENT_BINARY}"
    assert os.access(AGENT_BINARY, os.X_OK), f"Agent binary {AGENT_BINARY} is not executable"
    with open(AGENT_BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fast_organizer must be a compiled native executable"
    source = open(AGENT_SOURCE, "r", encoding="utf-8", errors="replace").read()
    assert "inotify" in source and "IN_CLOSE_WRITE" in source, "Source does not implement the required inotify close-write watch"
    assert "flock" in source and "LOCK_SH" in source, "Source does not acquire the required shared flock"


def test_current_files_locking_inotify_and_incremental_backups():
    reset_outputs()
    first_name = f"locked_{secrets.token_hex(5)}.wal"
    second_name = f"event_{secrets.token_hex(5)}.wal"
    first_path = os.path.join(INCOMING_DIR, first_name)
    second_staging = os.path.join("/tmp", second_name)
    first_records = make_wal(first_path, 37)
    second_records = make_wal(second_staging, 43)

    lock_fd = open(first_path, "rb")
    fcntl.flock(lock_fd.fileno(), fcntl.LOCK_EX)
    proc = subprocess.Popen([AGENT_BINARY], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(1.5)
        assert not os.path.exists(os.path.join(ARCHIVE_DIR, first_name)), "Organizer read and archived a file while an exclusive lock was held"

        before_first = tar_state()
        fcntl.flock(lock_fd.fileno(), fcntl.LOCK_UN)
        lock_fd.close()
        wait_for(os.path.join(ARCHIVE_DIR, first_name), 20)
        wait_for_new_tar(before_first, first_name)

        time.sleep(1.1)
        before_second = tar_state()
        shutil.copyfile(second_staging, os.path.join(INCOMING_DIR, second_name))
        wait_for(os.path.join(ARCHIVE_DIR, second_name), 20)
        wait_for_new_tar(before_second, second_name, forbidden_name=first_name)

        assert proc.poll() is None, "Organizer did not remain running to watch for new files"
    finally:
        if not lock_fd.closed:
            fcntl.flock(lock_fd.fileno(), fcntl.LOCK_UN)
            lock_fd.close()
        stop_agents(proc)
        if os.path.exists(second_staging):
            os.remove(second_staging)

    assert os.path.exists(COMPILED_DATA), f"Compiled data file missing at {COMPILED_DATA}"
    assert get_json_records(COMPILED_DATA) == first_records + second_records


def test_fast_organizer_speed_and_accuracy_on_unpredictable_wal():
    reset_outputs()
    basename = f"massive_{secrets.token_hex(8)}.wal"
    test_file = os.path.join("/tmp", basename)
    expected_generated = make_wal(test_file, 100000)

    t0 = time.time()
    legacy_proc = subprocess.run([LEGACY_PARSER, test_file], capture_output=True, text=True, timeout=120)
    legacy_time = time.time() - t0
    assert legacy_proc.returncode == 0, "Legacy parser failed to run on randomized test file"
    legacy_records = json.loads(legacy_proc.stdout)
    assert legacy_records == expected_generated, "Randomized WAL generation did not agree with the legacy parser"

    proc = subprocess.Popen([AGENT_BINARY], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(1)
        incoming_file = os.path.join(INCOMING_DIR, basename)
        archive_file = os.path.join(ARCHIVE_DIR, basename)
        t0 = time.time()
        shutil.copyfile(test_file, incoming_file)
        wait_for(archive_file, 60)
        agent_time = time.time() - t0
        assert proc.poll() is None, "Organizer exited instead of continuing to watch the incoming directory"
    finally:
        stop_agents(proc)
        if os.path.exists(test_file):
            os.remove(test_file)

    assert os.path.exists(COMPILED_DATA), f"Compiled data file missing at {COMPILED_DATA}"
    agent_records = get_json_records(COMPILED_DATA)
    assert len(agent_records) == len(legacy_records), f"Record count mismatch: expected {len(legacy_records)}, got {len(agent_records)}"
    for i in range(len(legacy_records)):
        assert agent_records[i] == legacy_records[i], f"Record mismatch at index {i}: expected {legacy_records[i]}, got {agent_records[i]}"

    speedup = legacy_time / agent_time
    assert speedup >= 10.0, f"Speedup too low: {speedup:.2f}x (Legacy: {legacy_time:.2f}s, Agent: {agent_time:.2f}s). Expected >= 10.0x"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
