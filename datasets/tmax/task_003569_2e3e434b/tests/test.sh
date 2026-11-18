#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import hashlib
import json
import os
import re
import secrets
import shutil
import stat
import subprocess
import threading
import time
import zipfile

import pytest

ARCHIVER = "/home/user/safe_archiver"
SOURCE = "/home/user/safe_archiver.cpp"
INPUT_FILE = "/home/user/config/live.json"
OUTPUT_DIR = "/home/user/backups"
MINIZ_DIR = "/app/miniz-3.0.2"


def test_build_artifacts_and_required_implementation():
    assert os.path.isfile(SOURCE), f"Source not found at {SOURCE}"
    assert os.path.isfile(ARCHIVER), f"Archiver executable not found at {ARCHIVER}"
    mode = os.stat(ARCHIVER).st_mode
    assert mode & stat.S_IXUSR, "safe_archiver is not executable"
    with open(ARCHIVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "safe_archiver must be a compiled ELF executable"

    with open(SOURCE, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    code = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    assert re.search(r"\bflock\s*\([^;]*\bLOCK_SH\b", code, re.S), "Source must acquire a shared flock"
    assert re.search(r"\bmmap\s*\(", code), "Source must use mmap"
    assert re.search(r"\bmunmap\s*\(", code), "Source must unmap mapped data"
    assert re.search(r"\bmz_zip_add_mem_to_archive_file_in_place\s*\(", code), "Source must use miniz's in-place archive API"
    assert re.search(r"\busleep\s*\(\s*10000(?:[uUlL]*)\s*\)", code), "Source must sleep for 10000 microseconds"

    with open(os.path.join(MINIZ_DIR, "Makefile"), "r", encoding="utf-8", errors="replace") as f:
        makefile = f.read()
    assert "clang-99" not in makefile, "The intentionally broken compiler setting was not fixed"
    assert re.search(r"(?m)^\s*CFLAGS\s*=.*(?:^|\s)-O3(?:\s|$)", makefile), "miniz must be built with -O3"

    library = os.path.join(MINIZ_DIR, "libminiz.a")
    assert os.path.isfile(library), "Fixed libminiz.a was not built"
    listing = subprocess.run(["ar", "t", library], capture_output=True, text=True, timeout=5)
    assert listing.returncode == 0 and "miniz.o" in listing.stdout.split(), "libminiz.a is not a valid archive containing miniz.o"

    symbols = subprocess.run(["nm", "-C", ARCHIVER], capture_output=True, text=True, timeout=5)
    assert symbols.returncode == 0, "Unable to inspect safe_archiver symbols"
    symbol_text = symbols.stdout + symbols.stderr
    for required in ("flock", "mmap", "munmap", "usleep", "mz_zip_add_mem_to_archive_file_in_place"):
        assert required in symbol_text, f"Compiled archiver does not reference required function {required}"


def writer_thread(stop_event, run_nonce, accepted_hashes, hashes_lock):
    """Continuously publishes distinct, complete 5MB JSON documents under LOCK_EX."""
    os.makedirs(os.path.dirname(INPUT_FILE), exist_ok=True)
    payload = "X" * (5 * 1024 * 1024 - 150)
    seq = 0
    while not stop_event.is_set():
        data = {"status": "active", "run": run_nonce, "seq": seq, "payload": payload}
        encoded = json.dumps(data, separators=(",", ":")).encode("utf-8")
        digest = hashlib.sha256(encoded).hexdigest()
        with open(INPUT_FILE, "a+b", buffering=0) as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            f.seek(0)
            f.truncate(0)
            f.write(encoded)
            f.flush()
            with hashes_lock:
                accepted_hashes.add(digest)
            fcntl.flock(f, fcntl.LOCK_UN)
        seq += 1
        time.sleep(0.005)


def test_safe_archiver_performance_and_correctness():
    assert os.path.isfile(ARCHIVER), f"Archiver executable not found at {ARCHIVER}"
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for name in os.listdir(OUTPUT_DIR):
        if name.endswith(".zip"):
            os.remove(os.path.join(OUTPUT_DIR, name))

    if os.path.exists(INPUT_FILE):
        os.remove(INPUT_FILE)

    run_nonce = secrets.token_hex(24)
    accepted_hashes = set()
    hashes_lock = threading.Lock()
    stop_event = threading.Event()
    writer = threading.Thread(
        target=writer_thread,
        args=(stop_event, run_nonce, accepted_hashes, hashes_lock),
        daemon=True,
    )
    writer.start()

    deadline = time.monotonic() + 5
    while True:
        with hashes_lock:
            ready = bool(accepted_hashes)
        if ready:
            break
        assert time.monotonic() < deadline, "Writer failed to create the initial configuration"
        time.sleep(0.01)

    start_time = time.monotonic()
    try:
        proc = subprocess.run(
            [ARCHIVER, INPUT_FILE, OUTPUT_DIR],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert proc.returncode == 0, (
            f"Archiver failed with return code {proc.returncode}. Stderr: {proc.stderr}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Archiver timed out after 30 seconds. This indicates it is either deadlocked or too slow.")
    finally:
        stop_event.set()
        writer.join(timeout=5)
        assert not writer.is_alive(), "Writer thread failed to stop"

    execution_time_ms = (time.monotonic() - start_time) * 1000.0
    with hashes_lock:
        published_hashes = set(accepted_hashes)

    expected_names = {f"snap_{i}.zip" for i in range(50)}
    produced_names = {name for name in os.listdir(OUTPUT_DIR) if name.endswith(".zip")}
    assert produced_names == expected_names, "Archiver must produce exactly snap_0.zip through snap_49.zip"

    valid_count = 0
    matching_count = 0
    for i in range(50):
        zip_path = os.path.join(OUTPUT_DIR, f"snap_{i}.zip")
        if not os.path.exists(zip_path):
            continue
        try:
            with zipfile.ZipFile(zip_path, "r") as zf:
                files = zf.namelist()
                if not files:
                    continue
                with zf.open(files[0]) as f:
                    raw = f.read()
                content = raw.decode("utf-8")
                parsed = json.loads(content)
                valid_count += 1

                assert len(files) == 1, f"snap_{i}.zip must contain exactly one configuration member"
                info = zf.getinfo(files[0])
                assert info.compress_type != zipfile.ZIP_STORED, f"snap_{i}.zip is not compressed"
                assert parsed.get("status") == "active" and parsed.get("run") == run_nonce
                assert isinstance(parsed.get("seq"), int)
                assert isinstance(parsed.get("payload"), str) and len(parsed["payload"]) == 5 * 1024 * 1024 - 150
                assert set(parsed["payload"]) == {"X"}
                assert hashlib.sha256(raw).hexdigest() in published_hashes, (
                    f"snap_{i}.zip does not contain a complete version actually published to live.json"
                )
                matching_count += 1
        except AssertionError:
            raise
        except Exception:
            pass

    # Preserve the original validity and throughput assertions.
    assert valid_count > 0, "No valid JSON archives were produced. Locking or compression failed completely."
    metric = execution_time_ms / valid_count
    assert metric <= 15.0, (
        f"Valid Snapshot Time metric failed: {metric:.2f} ms per valid snapshot. "
        f"Threshold is <= 15.0 ms. Valid count: {valid_count}/50, "
        f"Total time: {execution_time_ms:.2f} ms. "
        f"Ensure miniz is compiled with optimizations and mmap is used."
    )

    assert matching_count == 50, "Every snapshot must contain a complete configuration published during this run"
    assert execution_time_ms >= 430.0, "Archiver did not perform the required 10ms sleeps between 50 iterations"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
