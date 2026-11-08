#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import hashlib
import os
import random
import select
import shutil
import stat
import string
import subprocess
import tempfile
import time

import pytest

AGENT_SCRIPT = "/home/user/dedup_archive.py"
VENDORED = "/app/vendored/log-archiver-lib-1.2.0"
MAKEFILE = os.path.join(VENDORED, "Makefile")
FLOCK_SOURCE = os.path.join(VENDORED, "log_archiver", "flock_manager.py")
OBJECTS_DIR = "/home/user/backup_repo/objects"


@pytest.fixture(scope="session", autouse=True)
def verify_and_install_package():
    assert os.path.isfile(MAKEFILE), "Vendored Makefile is missing"
    assert os.path.isfile(FLOCK_SOURCE), "Vendored flock_manager.py is missing"

    with open(MAKEFILE, encoding="utf-8") as f:
        active_lines = [line for line in f if not line.lstrip().startswith("#")]
    assert not any("LOCK_DIR" in line and "/usr/bin/locked" in line for line in active_lines), \
        "Makefile still assigns LOCK_DIR to the read-only perturbed path"

    for target in ("test", "install"):
        proc = subprocess.run(
            ["make", target], cwd=VENDORED, capture_output=True, text=True, timeout=60
        )
        assert proc.returncode == 0, \
            f"make {target} failed:\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"

    env = os.environ.copy()
    env.pop("PYTHONPATH", None)
    proc = subprocess.run(
        ["python3", "-c",
         "from log_archiver.flock_manager import FlockManager; "
         "assert callable(FlockManager().lock)"],
        cwd="/tmp", env=env, capture_output=True, text=True
    )
    assert proc.returncode == 0, \
        f"make install did not install an importable FlockManager:\n{proc.stderr}"


def test_agent_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"


def test_flock_manager_waits_for_eagain_and_holds_lock():
    with tempfile.TemporaryDirectory() as td:
        lock_path = os.path.join(td, "lockfile")
        parent_file = open(lock_path, "a+")
        fcntl.flock(parent_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)

        code = r'''
import time
from log_archiver.flock_manager import FlockManager
f = open(__import__("sys").argv[1], "a+")
FlockManager().lock(f.fileno())
print("ACQUIRED", flush=True)
time.sleep(1.0)
'''
        child = subprocess.Popen(
            ["python3", "-c", code, lock_path], cwd="/tmp",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        try:
            ready, _, _ = select.select([child.stdout], [], [], 0.35)
            assert not ready, "FlockManager did not wait while the lock was held"
            assert child.poll() is None, \
                f"FlockManager crashed instead of waiting: {child.stderr.read()}"

            fcntl.flock(parent_file.fileno(), fcntl.LOCK_UN)
            ready, _, _ = select.select([child.stdout], [], [], 3.0)
            assert ready, "FlockManager did not acquire the lock after it was released"
            assert child.stdout.readline().strip() == "ACQUIRED"

            contender = open(lock_path, "a+")
            try:
                with pytest.raises(BlockingIOError):
                    fcntl.flock(contender.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            finally:
                contender.close()

            _, stderr = child.communicate(timeout=3)
            assert child.returncode == 0, stderr
        finally:
            try:
                fcntl.flock(parent_file.fileno(), fcntl.LOCK_UN)
            except OSError:
                pass
            parent_file.close()
            if child.poll() is None:
                child.kill()
                child.wait()


def record_hash(body):
    return hashlib.sha256(body.encode("utf-8")).hexdigest()


def expected_index(records):
    return "".join(f"{timestamp} -> {record_hash(body)}\n" for timestamp, body in records)


def assert_target(target, records):
    index_path = os.path.join(target, "index.txt")
    assert os.path.isfile(index_path), "Agent did not create index.txt"
    with open(index_path, "r", encoding="utf-8") as f:
        assert f.read() == expected_index(records)

    unique_bodies = {}
    for _, body in records:
        unique_bodies.setdefault(record_hash(body), body)

    expected_names = {"index.txt"} | {
        f"record_{digest}.log" for digest in unique_bodies
    }
    assert set(os.listdir(target)) == expected_names

    for digest, body in unique_bodies.items():
        object_path = os.path.join(OBJECTS_DIR, digest)
        link_path = os.path.join(target, f"record_{digest}.log")
        assert os.path.isfile(object_path), f"Missing object {digest}"
        assert stat.S_ISREG(os.lstat(object_path).st_mode)
        assert stat.S_ISREG(os.lstat(link_path).st_mode), \
            f"record_{digest}.log is not a hard link/regular file"
        with open(object_path, "rb") as f:
            assert f.read() == body.encode("utf-8"), f"Wrong contents for object {digest}"
        assert os.stat(object_path).st_ino == os.stat(link_path).st_ino, \
            f"record_{digest}.log is not hard-linked to its repository object"
        assert os.stat(object_path).st_dev == os.stat(link_path).st_dev


def run_agent(content, target, stdin=False, env=None):
    os.makedirs(target, exist_ok=True)
    if stdin:
        return subprocess.run(
            ["python3", AGENT_SCRIPT, "-", target], input=content,
            capture_output=True, text=True, env=env, timeout=60
        )
    input_path = target + ".input.log"
    with open(input_path, "w", encoding="utf-8") as f:
        f.write(content)
    return subprocess.run(
        ["python3", AGENT_SCRIPT, input_path, target],
        capture_output=True, text=True, env=env, timeout=60
    )


def test_deterministic_records_hardlinks_and_flockmanager_use():
    shutil.rmtree(OBJECTS_DIR, ignore_errors=True)
    os.makedirs(OBJECTS_DIR, exist_ok=True)

    records = [
        ("[2024-01-02 03:04:05]", "first line\nsecond line"),
        ("[2024-01-02 03:04:06]", "duplicate body"),
        ("[2024-01-02 03:04:07]", "duplicate body"),
        ("[2024-01-02 03:04:08]", "[2024-01-02 03:04:09] extra\nstill body"),
    ]
    content = "".join(f"{ts}\n{body}\n" for ts, body in records)

    with tempfile.TemporaryDirectory() as td:
        instrument = os.path.join(td, "instrument")
        os.makedirs(instrument)
        marker = os.path.join(td, "flock-used")
        with open(os.path.join(instrument, "sitecustomize.py"), "w", encoding="utf-8") as f:
            f.write(
                "import os\n"
                "from log_archiver.flock_manager import FlockManager\n"
                "_original_lock = FlockManager.lock\n"
                "def _checked_lock(self, fd):\n"
                "    with open(os.environ['FLOCK_MARKER'], 'a') as marker:\n"
                "        marker.write('lock\\n')\n"
                "    return _original_lock(self, fd)\n"
                "FlockManager.lock = _checked_lock\n"
            )
        env = os.environ.copy()
        env["PYTHONPATH"] = instrument + os.pathsep + env.get("PYTHONPATH", "")
        env["FLOCK_MARKER"] = marker

        target = os.path.join(td, "target-" + os.urandom(8).hex())
        proc = run_agent(content, target, env=env)
        assert proc.returncode == 0, proc.stderr
        assert_target(target, records)
        assert os.path.isfile(marker) and os.path.getsize(marker) > 0, \
            "dedup_archive.py did not use FlockManager while writing objects"


def test_standard_input():
    records = [
        ("[2025-05-06 07:08:09]", "stdin record\ncontinued"),
        ("[2025-05-06 07:08:10]", "another stdin record"),
    ]
    content = "".join(f"{ts}\n{body}\n" for ts, body in records)
    with tempfile.TemporaryDirectory() as td:
        target = os.path.join(td, "stdin-target-" + os.urandom(8).hex())
        proc = run_agent(content, target, stdin=True)
        assert proc.returncode == 0, proc.stderr
        assert_target(target, records)


def generate_random_log(num_records):
    records = []
    chunks = []
    for _ in range(num_records):
        timestamp = (
            f"[{random.randint(2000, 2025):04d}-{random.randint(1, 12):02d}-"
            f"{random.randint(1, 28):02d} {random.randint(0, 23):02d}:"
            f"{random.randint(0, 59):02d}:{random.randint(0, 59):02d}]"
        )
        body_lines = []
        for _ in range(random.randint(1, 20)):
            body_lines.append("".join(random.choices(
                string.ascii_letters + string.digits, k=random.randint(10, 100)
            )))
        body = "\n".join(body_lines)
        records.append((timestamp, body))
        chunks.append(f"{timestamp}\n{body}\n")
    return "".join(chunks), records


def test_fuzz_outputs_are_derived_from_input():
    random.seed(42)
    with tempfile.TemporaryDirectory() as td:
        for i in range(50):
            content, records = generate_random_log(random.randint(10, 500))
            target = os.path.join(td, f"target-{i}-{os.urandom(8).hex()}")
            proc = run_agent(content, target)
            assert proc.returncode == 0, f"Agent failed on input {i}:\n{proc.stderr}"
            assert_target(target, records)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
