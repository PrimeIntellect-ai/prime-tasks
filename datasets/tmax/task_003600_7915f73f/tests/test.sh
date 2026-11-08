#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/tracker_probe
cat << 'PROBE_EOF' > /tmp/tracker_probe/sitecustomize.py
import os
import concurrent.futures as _cf
import concurrent.futures.thread as _thread
import concurrent.futures.process as _process
import fcntl as _fcntl

_LOG = os.environ.get("TRACKER_PROBE_LOG")

def _event(text):
    if not _LOG:
        return
    fd = os.open(_LOG, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
    try:
        os.write(fd, (text + "\n").encode())
    finally:
        os.close(fd)

_OriginalThreadPoolExecutor = _thread.ThreadPoolExecutor
_OriginalProcessPoolExecutor = _process.ProcessPoolExecutor

class TrackedThreadPoolExecutor(_OriginalThreadPoolExecutor):
    def __init__(self, max_workers=None, *args, **kwargs):
        _event("executor:ThreadPoolExecutor:%s" % max_workers)
        super().__init__(max_workers=max_workers, *args, **kwargs)

    def submit(self, *args, **kwargs):
        _event("work:submit")
        return super().submit(*args, **kwargs)

    def map(self, *args, **kwargs):
        _event("work:map")
        return super().map(*args, **kwargs)

class TrackedProcessPoolExecutor(_OriginalProcessPoolExecutor):
    def __init__(self, max_workers=None, *args, **kwargs):
        _event("executor:ProcessPoolExecutor:%s" % max_workers)
        super().__init__(max_workers=max_workers, *args, **kwargs)

    def submit(self, *args, **kwargs):
        _event("work:submit")
        return super().submit(*args, **kwargs)

    def map(self, *args, **kwargs):
        _event("work:map")
        return super().map(*args, **kwargs)

_thread.ThreadPoolExecutor = TrackedThreadPoolExecutor
_process.ProcessPoolExecutor = TrackedProcessPoolExecutor
_cf.ThreadPoolExecutor = TrackedThreadPoolExecutor
_cf.ProcessPoolExecutor = TrackedProcessPoolExecutor

_original_flock = _fcntl.flock
_original_lockf = _fcntl.lockf

def tracked_flock(*args, **kwargs):
    _event("lock:flock")
    return _original_flock(*args, **kwargs)

def tracked_lockf(*args, **kwargs):
    _event("lock:lockf")
    return _original_lockf(*args, **kwargs)

_fcntl.flock = tracked_flock
_fcntl.lockf = tracked_lockf
PROBE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import stat
import subprocess
import uuid
import zipfile

import pytest

SCRIPT = "/home/user/tracker.py"
RESULTS = "/home/user/tracking_results.csv"
CONFIGS = "/home/user/configs"
PROBE_LOG = "/tmp/tracker_probe/events.log"
BASE_EXPECTED = [
    "backup.zip,1.2.0",
    "data.zip,2.0.1",
    "latest.zip,4.5.1",
]


def _run_tracker():
    if os.path.exists(RESULTS):
        os.unlink(RESULTS)
    if os.path.exists(PROBE_LOG):
        os.unlink(PROBE_LOG)

    env = os.environ.copy()
    env["TRACKER_PROBE_LOG"] = PROBE_LOG
    env["PYTHONPATH"] = "/tmp/tracker_probe" + (
        os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
    )
    completed = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert completed.returncode == 0, (
        f"tracker.py did not complete successfully. stdout={completed.stdout!r}, "
        f"stderr={completed.stderr!r}"
    )
    assert os.path.isfile(RESULTS), "tracker.py did not create tracking_results.csv"

    with open(PROBE_LOG, "r") as f:
        events = [line.strip() for line in f if line.strip()]
    assert any(e in ("executor:ThreadPoolExecutor:4", "executor:ProcessPoolExecutor:4") for e in events), (
        "tracker.py must actually construct ThreadPoolExecutor or ProcessPoolExecutor with max_workers=4"
    )
    assert any(e in ("work:submit", "work:map") for e in events), (
        "tracker.py constructed an executor but did not submit archive processing work to it"
    )
    assert any(e in ("lock:flock", "lock:lockf") for e in events), (
        "tracker.py did not actually use file locking while producing its results"
    )

    with open(RESULTS, "r") as f:
        return [line.strip() for line in f if line.strip()]


def _write_zip(path, version=None, include_meta=True, malformed_meta=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        if include_meta:
            if malformed_meta:
                zf.writestr("meta.json", "{not valid json")
            else:
                zf.writestr("meta.json", json.dumps({"version": version, "name": "dynamic"}))
        else:
            zf.writestr("dummy.txt", "dummy data")


def test_tracker_script_exists():
    """Test that the tracker.py script was created."""
    assert os.path.isfile("/home/user/tracker.py"), "/home/user/tracker.py does not exist."
    mode = os.lstat("/home/user/tracker.py").st_mode
    assert stat.S_ISREG(mode) and not os.path.islink("/home/user/tracker.py"), "tracker.py must be a regular file"


def test_tracker_executes_on_original_tree():
    lines = _run_tracker()
    assert sorted(lines) == sorted(BASE_EXPECTED), (
        f"Executed tracker output was incorrect. Expected {sorted(BASE_EXPECTED)}, got {sorted(lines)}"
    )


def test_results_file_exists():
    """Test that the tracking_results.csv file was created."""
    assert os.path.isfile("/home/user/tracking_results.csv"), "/home/user/tracking_results.csv does not exist."


def test_results_content():
    """Test that the tracking_results.csv contains the correct extracted versions."""
    results_path = "/home/user/tracking_results.csv"
    assert os.path.isfile(results_path), "Results file is missing, cannot check content."

    with open(results_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = [
        "backup.zip,1.2.0",
        "data.zip,2.0.1",
        "latest.zip,4.5.1"
    ]

    assert sorted(lines) == sorted(expected), f"Results content does not match expected output. Expected {sorted(expected)}, got {sorted(lines)}"


def test_dynamic_recursive_archive_processing():
    token = uuid.uuid4().hex
    root = os.path.join(CONFIGS, "verifier_" + token)
    first_name = "dynamic_" + token[:10] + ".zip"
    second_name = "nested_" + token[10:20] + ".zip"
    first_version = "v-" + uuid.uuid4().hex
    second_version = "v-" + uuid.uuid4().hex

    try:
        _write_zip(os.path.join(root, first_name), first_version)
        _write_zip(os.path.join(root, "one", "two", "three", second_name), second_version)
        _write_zip(os.path.join(root, "no_meta.zip"), include_meta=False)
        _write_zip(os.path.join(root, "bad_json.zip"), malformed_meta=True)

        with open(os.path.join(root, "not_a_zip.zip"), "wb") as f:
            f.write(os.urandom(257))

        bad_crc = os.path.join(root, "bad_crc.zip")
        marker = ("PAYLOAD-" + uuid.uuid4().hex).encode()
        with zipfile.ZipFile(bad_crc, "w", compression=zipfile.ZIP_STORED) as zf:
            zf.writestr("meta.json", json.dumps({"version": "must-not-appear"}))
            zf.writestr("payload.bin", marker)
        data = bytearray(open(bad_crc, "rb").read())
        position = data.find(marker)
        assert position >= 0
        data[position] ^= 0x01
        with open(bad_crc, "wb") as f:
            f.write(data)

        lines = _run_tracker()
        expected = BASE_EXPECTED + [
            f"{first_name},{first_version}",
            f"{second_name},{second_version}",
        ]
        assert sorted(lines) == sorted(expected), (
            "tracker.py failed randomized recursive/integrity/meta tests. "
            f"Expected {sorted(expected)}, got {sorted(lines)}"
        )
    finally:
        shutil.rmtree(root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
