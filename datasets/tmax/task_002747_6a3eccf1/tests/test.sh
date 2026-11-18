#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/sitecustomize.py
import fcntl
import os

_trace_dir = os.environ.get("SAR_LOCK_TRACE")
_real_flock = fcntl.flock
_real_lockf = fcntl.lockf

def _fd_number(fd):
    return fd if isinstance(fd, int) else fd.fileno()

def _record(kind, fd, operation):
    if not _trace_dir:
        return
    try:
        number = _fd_number(fd)
        try:
            target = os.readlink(f"/proc/self/fd/{number}")
        except OSError:
            target = "?"
        line = f"{kind} {operation} {target}\n".encode()
        out = os.open(os.path.join(_trace_dir, str(os.getpid())),
                      os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
        try:
            os.write(out, line)
        finally:
            os.close(out)
    except Exception:
        pass

def flock(fd, operation):
    result = _real_flock(fd, operation)
    _record("flock", fd, operation)
    return result

def lockf(fd, operation, length=0, start=0, whence=0):
    result = _real_lockf(fd, operation, length, start, whence)
    _record("lockf", fd, operation)
    return result

fcntl.flock = flock
fcntl.lockf = lockf
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import os
import random
import secrets
import shutil
import struct
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/detector.py"
LOG_PATH = "/home/user/scan_log.txt"
CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"
TRACER_DIR = "/tmp/sar_lock_traces"
TRACER_PYTHONPATH = "/tmp"


def reset_trace_dir():
    shutil.rmtree(TRACER_DIR, ignore_errors=True)
    os.makedirs(TRACER_DIR, mode=0o777)


def run_detector(filepath):
    cmd = ["python3", SCRIPT_PATH, filepath]
    env = os.environ.copy()
    env["SAR_LOCK_TRACE"] = TRACER_DIR
    env["PYTHONPATH"] = TRACER_PYTHONPATH + (
        os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
    )
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=5, env=env)
        return filepath, result.returncode, result.stdout.strip()
    except subprocess.TimeoutExpired:
        return filepath, -1, "TIMEOUT"
    except Exception as e:
        return filepath, -1, str(e)


def assert_locking_was_used(invocation_count):
    traces = []
    for name in os.listdir(TRACER_DIR):
        path = os.path.join(TRACER_DIR, name)
        if os.path.isfile(path):
            with open(path, "r", errors="replace") as f:
                traces.append(f.read().splitlines())

    assert len(traces) == invocation_count, (
        f"Only {len(traces)} of {invocation_count} detector invocations actually "
        "called fcntl.flock/lockf"
    )
    for events in traces:
        exclusive = []
        for event in events:
            parts = event.split(" ", 2)
            if len(parts) == 3:
                try:
                    operation = int(parts[1])
                except ValueError:
                    continue
                if operation & 2:  # fcntl.LOCK_EX
                    exclusive.append(parts[2])
        assert exclusive, "A detector invocation did not acquire an exclusive file lock"
        assert any(
            target == LOG_PATH
            or target.startswith(LOG_PATH + ".")
            or (target.startswith("/home/user/") and "lock" in os.path.basename(target).lower())
            for target in exclusive
        ), "Exclusive lock was not taken on the scan log or a scan-log lock file"


def test_detector_exists():
    assert os.path.exists(SCRIPT_PATH), f"Detector script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"


def test_adversarial_corpus_and_locking():
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)
    reset_trace_dir()

    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR)
                   if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR)
                  if os.path.isfile(os.path.join(EVIL_DIR, f))]

    all_files = clean_files + evil_files
    assert len(clean_files) > 0, "No clean corpus files found"
    assert len(evil_files) > 0, "No evil corpus files found"

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=25) as executor:
        futures = {executor.submit(run_detector, f): f for f in all_files}
        for future in concurrent.futures.as_completed(futures):
            results.append(future.result())

    failed_clean = []
    failed_evil = []
    for filepath, retcode, stdout in results:
        if filepath in clean_files:
            if retcode != 0 or stdout != "ACCEPT":
                failed_clean.append((filepath, retcode, stdout))
        else:
            if retcode != 1 or stdout != "REJECT":
                failed_evil.append((filepath, retcode, stdout))

    error_msgs = []
    if failed_clean:
        examples = [os.path.basename(f[0]) for f in failed_clean[:5]]
        error_msgs.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected. Examples: {examples}")
    if failed_evil:
        examples = [os.path.basename(f[0]) for f in failed_evil[:5]]
        error_msgs.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed/accepted. Examples: {examples}")
    assert not error_msgs, " | ".join(error_msgs)

    assert os.path.exists(LOG_PATH), f"Log file not created at {LOG_PATH}"
    with open(LOG_PATH, "r") as f:
        log_lines = f.read().splitlines()

    assert len(log_lines) == len(all_files), (
        f"Log file has {len(log_lines)} entries, expected {len(all_files)}. "
        "This indicates file locking failed during concurrent writes."
    )

    log_entries = set(log_lines)
    expected_entries = {f"{f} ACCEPT" for f in clean_files}
    expected_entries.update(f"{f} REJECT" for f in evil_files)
    missing = expected_entries - log_entries
    extra = log_entries - expected_entries
    assert not missing and not extra, (
        "Log file contents do not match expected output exactly. "
        "Concurrent writes may have corrupted the lines (e.g., interleaved characters)."
    )
    assert_locking_was_used(len(all_files))


def write_sar(path, entries):
    with open(path, "wb") as f:
        f.write(b"SAR\x00")
        f.write(struct.pack("<H", len(entries)))
        for name, content in entries:
            encoded = name.encode("ascii")
            f.write(struct.pack("<H", len(encoded)))
            f.write(encoded)
            f.write(struct.pack("<I", len(content)))
            f.write(content)


def is_malicious(entries):
    for name, _ in entries:
        if name.startswith("/") or ".." in name.split("/"):
            return True
    return False


def test_generated_archives_are_parsed_by_content():
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)
    reset_trace_dir()

    root = tempfile.mkdtemp(prefix="uploads_", dir="/tmp")
    rng = random.SystemRandom()
    expected = {}
    safe_names = [
        "plain.txt", "docs/readme.txt", "a/./b", "a/.../b",
        "a/..hidden/b", "..txt", "back\\..\\file", "nested/deep/item.bin"
    ]
    bad_names = [
        "/absolute/target", "../escape", "dir/../escape",
        "dir/sub/../../escape", "tail/.."
    ]

    try:
        for i in range(220):
            entries = []
            for j in range(1 + rng.randrange(4)):
                name = rng.choice(safe_names)
                name = name.replace("plain", secrets.token_hex(4))
                payload = os.urandom(rng.randrange(0, 80)) + b"../not-a-header-field"
                entries.append((name, payload))

            if i % 2:
                position = rng.randrange(len(entries) + 1)
                bad = rng.choice(bad_names) + "_" + secrets.token_hex(5)
                entries.insert(position, (bad, os.urandom(rng.randrange(0, 80))))

            archive = os.path.join(root, secrets.token_hex(16) + ".sar")
            write_sar(archive, entries)
            expected[archive] = "REJECT" if is_malicious(entries) else "ACCEPT"

        paths = list(expected)
        rng.shuffle(paths)
        results = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=40) as executor:
            futures = [executor.submit(run_detector, path) for path in paths]
            for future in concurrent.futures.as_completed(futures):
                results.append(future.result())

        failures = []
        for path, retcode, stdout in results:
            decision = expected[path]
            wanted_code = 0 if decision == "ACCEPT" else 1
            if retcode != wanted_code or stdout != decision:
                failures.append((os.path.basename(path), decision, retcode, stdout))
        assert not failures, f"Generated SAR decisions were incorrect: {failures[:8]}"

        assert os.path.exists(LOG_PATH), "Log file was not created for generated archives"
        with open(LOG_PATH, "r") as f:
            lines = f.read().splitlines()
        wanted_lines = {f"{path} {decision}" for path, decision in expected.items()}
        assert len(lines) == len(expected), (
            f"Log file has {len(lines)} generated entries, expected {len(expected)}"
        )
        assert set(lines) == wanted_lines, "Generated-archive log entries are missing, extra, or corrupted"
        assert_locking_was_used(len(expected))
    finally:
        shutil.rmtree(root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
