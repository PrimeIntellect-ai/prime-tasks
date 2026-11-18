#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import atexit
import os
import shutil
import subprocess
import tempfile
import time
import uuid

import pytest

EXPORTER = "/home/user/exporter"
SCRIPT = os.path.join(EXPORTER, "lifecycle.sh")
BIN = os.path.join(EXPORTER, "bin")
PIDFILE = os.path.join(EXPORTER, "pidfile")
_spawned_pids = set()


def pid_exists(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def wait_for_pid_exit(pid, timeout=3.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not pid_exists(pid):
            return True
        time.sleep(0.05)
    return not pid_exists(pid)


def cleanup_processes():
    for pid in list(_spawned_pids):
        if pid_exists(pid):
            try:
                os.kill(pid, 15)
            except OSError:
                pass
    if os.path.isfile(PIDFILE):
        try:
            with open(PIDFILE) as f:
                value = f.read().strip()
            if value.isdigit() and pid_exists(int(value)):
                os.kill(int(value), 15)
        except OSError:
            pass


atexit.register(cleanup_processes)


def get_directory_size(path):
    total_size = 0
    for dirpath, _, filenames in os.walk(path):
        for name in filenames:
            full_path = os.path.join(dirpath, name)
            if not os.path.islink(full_path):
                total_size += os.path.getsize(full_path)
    return total_size


def expected_metric(directory):
    return f'mock_container_storage_bytes{{path="{directory}"}} {get_directory_size(directory)}\n'


def wait_for_metric(metrics_path, expected, timeout=3.5):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            with open(metrics_path, "r") as f:
                last = f.read()
            if last == expected:
                return
        except (FileNotFoundError, UnicodeDecodeError):
            pass
        time.sleep(0.05)
    pytest.fail(f"Metric did not update to the expected exact content. Expected {expected!r}, last read {last!r}")


def test_01_main_cpp_exists():
    path = os.path.join(EXPORTER, "main.cpp")
    assert os.path.isfile(path), f"C++ source file {path} does not exist."


def test_02_lifecycle_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Lifecycle script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Lifecycle script {SCRIPT} is not executable."


def test_03_bin_exists_and_executable():
    assert os.path.isfile(BIN), f"Executable {BIN} does not exist. Did you run './lifecycle.sh build'?"
    assert os.access(BIN, os.X_OK), f"Executable {BIN} is not executable."


def test_04_metrics_file_content():
    metrics_path = "/home/user/metrics.prom"
    container_path = "/home/user/mock_container"
    time.sleep(1.5)
    assert os.path.isfile(metrics_path), f"Metrics file {metrics_path} does not exist. Is the daemon running?"

    expected_line = f'mock_container_storage_bytes{{path="{container_path}"}} {get_directory_size(container_path)}'
    with open(metrics_path, "r") as f:
        content = f.read()

    assert content.strip() == expected_line, (
        f"Metrics file content does not match expected.\nExpected: '{expected_line}'\nFound: '{content.strip()}'"
    )
    assert content == expected_line + "\n", "Metrics output must be exactly one line ending in a newline."


def test_05_pidfile_and_process():
    assert os.path.isfile(PIDFILE), f"Pidfile {PIDFILE} does not exist."
    with open(PIDFILE, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"Pidfile does not contain a valid PID: '{pid_str}'"
    pid = int(pid_str)
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} is not running.")


def test_06_lifecycle_stop():
    assert os.path.isfile(PIDFILE), "Pidfile missing before stop command."
    with open(PIDFILE, "r") as f:
        pid = int(f.read().strip())

    result = subprocess.run([SCRIPT, "stop"], cwd=EXPORTER, capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, f"Stop command failed with return code {result.returncode}\nStderr: {result.stderr}"
    assert wait_for_pid_exit(pid, 2.0), f"Process with PID {pid} is still running after stop command."
    assert not os.path.isfile(PIDFILE), f"Pidfile {PIDFILE} was not deleted after stop command."


def test_07_build_recompiles_source_and_argument_count_is_enforced():
    os.remove(BIN)
    result = subprocess.run([SCRIPT, "build"], cwd=EXPORTER, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"Build command failed.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    assert os.path.isfile(BIN), "Build command did not recreate /home/user/exporter/bin."
    assert os.access(BIN, os.X_OK), "The rebuilt bin is not executable."

    reference_bin = os.path.join("/tmp", "exporter-reference-" + uuid.uuid4().hex)
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", os.path.join(EXPORTER, "main.cpp"), "-o", reference_bin],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"main.cpp does not compile as C++17 with -O2.\nStderr: {compile_result.stderr}"
    )
    assert os.path.isfile(reference_bin) and os.access(reference_bin, os.X_OK)

    for args in ([], ["/tmp"], ["/tmp", "/tmp/out", "extra"]):
        proc = subprocess.Popen([reference_bin] + args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            proc.wait(timeout=1.5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
            pytest.fail(f"Daemon did not reject invalid argument list: {args!r}")

    os.remove(reference_bin)


def test_08_compiled_main_cpp_recursively_and_periodically_monitors_arbitrary_paths():
    root = tempfile.mkdtemp(prefix="source-monitor-", dir="/home/user")
    monitor = os.path.join(root, "arbitrary container")
    nested = os.path.join(monitor, "one", "two")
    os.makedirs(nested)
    metrics = os.path.join(root, "source-output.prom")
    with open(os.path.join(monitor, "top.bin"), "wb") as f:
        f.write(os.urandom(731))
    with open(os.path.join(nested, "deep.bin"), "wb") as f:
        f.write(os.urandom(1297))
    with open(metrics, "w") as f:
        f.write("stale data that must be overwritten\nsecond line\n")

    reference_bin = os.path.join(root, "compiled-from-main")
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", os.path.join(EXPORTER, "main.cpp"), "-o", reference_bin],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr

    proc = subprocess.Popen([reference_bin, monitor, metrics], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    _spawned_pids.add(proc.pid)
    try:
        wait_for_metric(metrics, expected_metric(monitor))
        assert proc.poll() is None, "Daemon exited instead of continuing its infinite update loop."

        with open(os.path.join(nested, "new-file.bin"), "wb") as f:
            f.write(os.urandom(2459))
        wait_for_metric(metrics, expected_metric(monitor))
        assert proc.poll() is None, "Daemon stopped after its first metric update."
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        _spawned_pids.discard(proc.pid)
        shutil.rmtree(root, ignore_errors=True)


def test_09_lifecycle_start_uses_arguments_updates_periodically_and_stop_terminates_it():
    root = tempfile.mkdtemp(prefix="lifecycle-monitor-", dir="/home/user")
    monitor = os.path.join(root, "random-" + uuid.uuid4().hex)
    nested = os.path.join(monitor, "nested", "deeper")
    os.makedirs(nested)
    metrics = os.path.join(root, "random-metrics-" + uuid.uuid4().hex + ".prom")

    with open(os.path.join(monitor, "a.bin"), "wb") as f:
        f.write(os.urandom(887))
    with open(os.path.join(nested, "b.bin"), "wb") as f:
        f.write(os.urandom(1663))
    with open(metrics, "w") as f:
        f.write("old contents\nwhich must disappear\n")

    result = subprocess.run([SCRIPT, "start", monitor, metrics], cwd=EXPORTER, capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, f"Start command failed.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    assert os.path.isfile(PIDFILE), "Start command did not create the pidfile."
    with open(PIDFILE) as f:
        pid_text = f.read().strip()
    assert pid_text.isdigit(), f"Pidfile does not contain a numeric PID: {pid_text!r}"
    pid = int(pid_text)
    _spawned_pids.add(pid)

    try:
        assert pid_exists(pid), "PID written by start is not running."
        proc_exe = f"/proc/{pid}/exe"
        assert os.path.exists(proc_exe), "Started PID has no executable."
        assert os.path.samefile(proc_exe, BIN), "Pidfile does not identify the compiled monitoring daemon."

        wait_for_metric(metrics, expected_metric(monitor))

        with open(os.path.join(nested, "later.bin"), "wb") as f:
            f.write(os.urandom(3011))
        wait_for_metric(metrics, expected_metric(monitor))

        os.remove(os.path.join(monitor, "a.bin"))
        with open(os.path.join(nested, "b.bin"), "ab") as f:
            f.write(os.urandom(419))
        wait_for_metric(metrics, expected_metric(monitor))

        stop_result = subprocess.run([SCRIPT, "stop"], cwd=EXPORTER, capture_output=True, text=True, timeout=5)
        assert stop_result.returncode == 0, f"Stop command failed.\nStderr: {stop_result.stderr}"
        assert wait_for_pid_exit(pid, 2.0), f"Process {pid} remained alive after lifecycle stop."
        assert not os.path.exists(PIDFILE), "Stop command did not remove the pidfile."
        _spawned_pids.discard(pid)
    finally:
        if pid_exists(pid):
            try:
                os.kill(pid, 15)
            except OSError:
                pass
        shutil.rmtree(root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
