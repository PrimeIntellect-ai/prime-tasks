#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import importlib
import io
import os
import shutil
import signal
import socket
import subprocess
import sys
import tarfile
import tempfile
import time
import uuid

import pytest
import requests

LOCKER_FILE = "/app/pylogarchiver-1.0.0/pylogarchiver/locker.py"
LOG_ROOT = "/app/data/logs"
URL = "http://127.0.0.1:8080/download"
MARKER = "/tmp/safe_archiver_calls.log"
SERVER_PROCESS = None


def test_pylogarchiver_bug_fixed():
    assert os.path.isfile(LOCKER_FILE), f"File {LOCKER_FILE} is missing."
    with open(LOCKER_FILE, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "fcntl.LOCK_EX | fcntl.LOCK_NB" in content, (
        "The bug in locker.py was not fixed. Expected "
        "'fcntl.LOCK_EX | fcntl.LOCK_NB'."
    )
    assert "fcntl.LOCK_EX & fcntl.LOCK_NB" not in content, (
        "The bug in locker.py is still present."
    )


def test_installed_package_and_locking_behavior(tmp_path, monkeypatch):
    # Import from outside the vendored project directory, proving the package is
    # available to the service's Python environment.
    os.chdir("/tmp")
    for name in list(sys.modules):
        if name == "pylogarchiver" or name.startswith("pylogarchiver."):
            del sys.modules[name]
    package = importlib.import_module("pylogarchiver")
    locker_module = importlib.import_module("pylogarchiver.locker")
    archiver_module = importlib.import_module("pylogarchiver.archiver")
    assert hasattr(package, "SafeArchiver")

    # Exercise FileLocker.lock and verify the exact flags passed to flock.
    calls = []
    monkeypatch.setattr(locker_module.fcntl, "flock", lambda fd, flags: calls.append((fd, flags)))
    locker_module.FileLocker(123).lock()
    assert calls == [(123, fcntl.LOCK_EX | fcntl.LOCK_NB)]

    # Verify that SafeArchiver actually locks and unlocks every archived file.
    events = []

    class RecordingLocker:
        def __init__(self, fd):
            events.append(("init", fd))
        def lock(self):
            events.append(("lock", None))
        def unlock(self):
            events.append(("unlock", None))

    monkeypatch.setattr(archiver_module, "FileLocker", RecordingLocker)
    source = tmp_path / "logs"
    source.mkdir()
    (source / "one.log").write_bytes(b"one\n")
    output = tmp_path / "direct.tar.gz"
    archiver_module.SafeArchiver(str(output)).add_directory(str(source))
    assert output.is_file()
    assert [event[0] for event in events].count("lock") == 1
    assert [event[0] for event in events].count("unlock") == 1


def listening_pids(port):
    inodes = set()
    target = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == target and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    result.add(int(entry))
                    break
        except OSError:
            continue
    return result


def stop_current_server():
    pids = listening_pids(8080)
    for pid in pids:
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 3
    while time.time() < deadline and listening_pids(8080):
        time.sleep(0.05)
    for pid in listening_pids(8080):
        os.kill(pid, signal.SIGKILL)
    deadline = time.time() + 2
    while time.time() < deadline and listening_pids(8080):
        time.sleep(0.05)
    assert not listening_pids(8080), "Could not stop the existing service for instrumentation"


def start_instrumented_server():
    global SERVER_PROCESS
    assert os.path.isfile("/app/server.py"), "/app/server.py is missing"

    # Copy the genuinely installed package under a private name, then put a
    # transparent recording wrapper in front of SafeArchiver. This demonstrates
    # that the endpoint's executed code invokes the required class rather than
    # merely mentioning it in source or returning a constant archive.
    os.chdir("/tmp")
    for name in list(sys.modules):
        if name == "pylogarchiver" or name.startswith("pylogarchiver."):
            del sys.modules[name]
    installed = importlib.import_module("pylogarchiver")
    package_dir = os.path.dirname(os.path.abspath(installed.__file__))

    instrument = "/tmp/pylogarchiver_instrument"
    shutil.rmtree(instrument, ignore_errors=True)
    os.makedirs(instrument)
    shutil.copytree(package_dir, os.path.join(instrument, "_real_pylogarchiver"))
    shim = os.path.join(instrument, "pylogarchiver")
    os.makedirs(shim)

    wrapper = r'''from _real_pylogarchiver import SafeArchiver as _RealSafeArchiver
MARKER = "/tmp/safe_archiver_calls.log"
class SafeArchiver:
    def __init__(self, output_path):
        with open(MARKER, "a") as f:
            f.write("INIT:" + str(output_path) + "\\n")
        self._real = _RealSafeArchiver(output_path)
    def add_directory(self, directory):
        with open(MARKER, "a") as f:
            f.write("ADD:" + os.path.abspath(directory) + "\\n")
        return self._real.add_directory(directory)
import os
'''
    with open(os.path.join(shim, "__init__.py"), "w") as f:
        f.write(wrapper)
    with open(os.path.join(shim, "archiver.py"), "w") as f:
        f.write(wrapper)
    real_locker = os.path.join(package_dir, "locker.py")
    if os.path.isfile(real_locker):
        shutil.copy2(real_locker, os.path.join(shim, "locker.py"))

    try:
        os.unlink(MARKER)
    except FileNotFoundError:
        pass
    stop_current_server()

    env = os.environ.copy()
    env["PYTHONPATH"] = instrument + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    log = open("/tmp/instrumented_server.log", "wb")
    launcher = (
        "import runpy,sys; "
        f"sys.path.insert(0, {instrument!r}); "
        "runpy.run_path('/app/server.py', run_name='__main__')"
    )
    SERVER_PROCESS = subprocess.Popen(
        [sys.executable, "-c", launcher],
        cwd="/tmp",
        env=env,
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )

    deadline = time.time() + 10
    while time.time() < deadline:
        if SERVER_PROCESS.poll() is not None:
            break
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    details = ""
    try:
        details = open("/tmp/instrumented_server.log", errors="replace").read()[-2000:]
    except OSError:
        pass
    pytest.fail(f"/app/server.py did not bind to 127.0.0.1:8080. Output: {details}")


def snapshot_logs():
    result = {}
    for root, _, files in os.walk(LOG_ROOT):
        for filename in files:
            path = os.path.join(root, filename)
            if os.path.isfile(path):
                relative = os.path.relpath(path, LOG_ROOT).replace(os.sep, "/")
                with open(path, "rb") as f:
                    result[relative] = f.read()
    return result


def request_and_validate(expected):
    try:
        response = requests.get(URL, timeout=10)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}: {e}")

    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. "
        f"Response: {response.text[:200]}"
    )
    media_type = response.headers.get("Content-Type", "").split(";", 1)[0].strip().lower()
    assert media_type in {"application/gzip", "application/x-gzip"}, (
        f"Expected a gzip content type, got {response.headers.get('Content-Type')!r}"
    )

    try:
        with tarfile.open(fileobj=io.BytesIO(response.content), mode="r:gz") as tar:
            members = tar.getmembers()
            assert len(members) > 0, "The returned tar.gz archive is empty."
            files = [m for m in members if m.isfile()]
            assert len(files) > 0, "No files found in the tar.gz archive."
            names = [m.name.lstrip("./") for m in files]
            assert len(names) == len(set(names)), "Archive contains duplicate file paths"
            assert set(names) == set(expected), (
                f"Archive paths differ from /app/data/logs: expected {sorted(expected)}, got {sorted(names)}"
            )
            for member, name in zip(files, names):
                extracted = tar.extractfile(member)
                assert extracted is not None, f"Failed to extract {member.name} from archive."
                content = extracted.read()
                assert content == expected[name], f"Archived content for {name} does not match the log file"
                # Preserve the original torn-line assertion.
                if len(content) > 0:
                    assert content.endswith(b"\n"), f"File {member.name} contains a torn line at the end."
    except tarfile.TarError as e:
        pytest.fail(f"The response body is not a valid tar.gz archive: {e}")


def test_service_download_endpoint_multiple_requests():
    start_instrumented_server()
    probe = os.path.join(LOG_ROOT, f"verifier_{uuid.uuid4().hex}.log")
    try:
        with open(probe, "wb") as f:
            f.write(b"first unique verifier payload\n")
        first = snapshot_logs()
        request_and_validate(first)

        with open(probe, "wb") as f:
            f.write(b"second changed verifier payload\n")
        second = snapshot_logs()
        assert first[os.path.basename(probe)] != second[os.path.basename(probe)]
        request_and_validate(second)

        assert os.path.isfile(MARKER), "The running endpoint never instantiated pylogarchiver.SafeArchiver"
        marker = open(MARKER).read().splitlines()
        assert sum(line.startswith("INIT:") for line in marker) >= 2
        expected_add = "ADD:" + os.path.abspath(LOG_ROOT)
        assert marker.count(expected_add) >= 2, (
            "The endpoint did not call SafeArchiver.add_directory('/app/data/logs') for both requests"
        )
    finally:
        try:
            os.unlink(probe)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
