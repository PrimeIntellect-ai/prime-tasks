#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import random
import shutil
import signal
import subprocess
import tempfile
import time
import uuid

import pytest


def test_symlink_created():
    link_path = "/home/user/mnt_target"
    assert os.path.islink(link_path), f"Symlink {link_path} is missing or not a symlink."
    target = os.readlink(link_path)
    assert target == "/home/user/app_data", f"Symlink points to '{target}' instead of '/home/user/app_data'."


def test_app_log_content():
    log_path = "/home/user/app_data/app.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."
    with open(log_path, "r") as f:
        content = f.read()
    expected_text = "1.2.0 RUNNING MODE=PRODUCTION"
    assert expected_text in content, f"Expected '{expected_text}' in app.log, but got: '{content}'."


def test_rollout_script():
    script_path = "/home/user/rollout.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_worker_cpp_exists():
    cpp_path = "/home/user/src/worker.cpp"
    assert os.path.isfile(cpp_path), f"C++ source file {cpp_path} is missing."


def test_worker_pid_and_process():
    pid_file = "/home/user/run/worker.pid"
    assert os.path.isfile(pid_file), f"PID file {pid_file} is missing."

    with open(pid_file, "r") as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), f"PID file does not contain a valid integer: '{pid_str}'."
    pid = int(pid_str)

    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process {pid} read from {pid_file} is not running.")

    cmdline_path = f"/proc/{pid}/cmdline"
    if os.path.isfile(cmdline_path):
        with open(cmdline_path, "r") as f:
            cmdline = f.read().replace('\0', ' ')
        assert "worker" in cmdline, f"Process {pid} does not appear to be the worker process. Command line: '{cmdline}'."


def stop_process(pid):
    if not pid:
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        return
    for _ in range(20):
        if not os.path.exists(f"/proc/{pid}"):
            return
        time.sleep(0.05)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def read_pid(path):
    try:
        text = pathlib.Path(path).read_text().strip()
        return int(text) if text.isdigit() else None
    except OSError:
        return None


def wait_for_log(path, expected, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if expected in pathlib.Path(path).read_text():
                return
        except OSError:
            pass
        time.sleep(0.1)
    actual = pathlib.Path(path).read_text() if pathlib.Path(path).exists() else "<missing>"
    pytest.fail(f"Expected {expected!r} in {path}, but got {actual!r}")


def assert_real_worker(pid, expected_version, expected_mount):
    assert pid is not None, "rollout did not write a numeric worker PID"
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"rollout worker process {pid} is not running")
    stat = pathlib.Path(f"/proc/{pid}/stat").read_text().split()
    assert len(stat) > 2 and stat[2] != "Z", f"worker process {pid} is a zombie"
    exe = os.path.realpath(f"/proc/{pid}/exe")
    assert exe == "/home/user/bin/worker", f"PID {pid} runs {exe}, not the compiled worker"
    argv = pathlib.Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    argv = [x.decode(errors="replace") for x in argv if x]
    assert len(argv) == 3, f"worker received the wrong argument count: {argv}"
    assert argv[1:] == [expected_version, expected_mount], f"worker arguments were {argv[1:]}"


def test_worker_and_rollout_behavior(tmp_path):
    source = pathlib.Path("/home/user/src/worker.cpp")
    direct_binary = tmp_path / "direct-worker"
    compile_result = subprocess.run(
        ["g++", str(source), "-o", str(direct_binary)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, f"worker.cpp does not compile:\n{compile_result.stderr}"

    # Exactly two arguments are required; invalid invocations must not become services.
    for args in ([], ["only-version"], ["v", "/tmp", "extra"]):
        proc = subprocess.Popen([str(direct_binary), *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            stop_process(proc.pid)
            pytest.fail(f"worker did not reject invalid arguments: {args}")

    direct_mount = tmp_path / "direct-mount"
    direct_mount.mkdir()
    first_line = "MODE=VERIFY_" + uuid.uuid4().hex
    (direct_mount / "config.txt").write_text(first_line + "\nIGNORED=SECOND_LINE\n")
    (direct_mount / "app.log").write_text("preexisting-line\n")
    direct_version = f"verify-{uuid.uuid4().hex}"
    direct_expected = f"{direct_version} RUNNING {first_line}"
    proc = subprocess.Popen(
        [str(direct_binary), direct_version, str(direct_mount)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        time.sleep(0.3)
        assert proc.poll() is None, "worker did not remain running"
        wait_for_log(direct_mount / "app.log", direct_expected)
        contents = (direct_mount / "app.log").read_text().splitlines()
        assert contents == ["preexisting-line", direct_expected], \
            f"worker did not append exactly the required line: {contents}"
    finally:
        stop_process(proc.pid)

    history_path = pathlib.Path("/home/user/build_history.txt")
    fstab_path = pathlib.Path("/home/user/vmounts.fstab")
    script_path = pathlib.Path("/home/user/rollout.sh")
    pid_path = pathlib.Path("/home/user/run/worker.pid")
    binary_path = pathlib.Path("/home/user/bin/worker")
    original_history = history_path.read_bytes()
    original_fstab = fstab_path.read_bytes()
    original_source = source.read_bytes()

    old_pid = read_pid(pid_path)
    stop_process(old_pid)

    token = uuid.uuid4().hex
    source_dir = tmp_path / ("volume-" + token)
    target_dir = tmp_path / ("mount-" + token)
    source_dir.mkdir()
    config_line = "MODE=DYNAMIC_" + token
    (source_dir / "config.txt").write_text(config_line + "\nSHOULD_NOT_BE_READ\n")
    (source_dir / "app.log").write_text("existing-dynamic-entry\n")

    base = random.randint(30, 70)
    expected_version = f"{base + 1}.7.3"
    lower_success = f"{base}.99.99"
    failed_higher = f"{base + 20}.0.0"
    history = (
        f"build_id=901 version={expected_version} status=SUCCESS\n"
        f"build_id=902 version={failed_higher} status=FAILED\n"
        f"build_id=903 version={lower_success} status=SUCCESS\n"
        f"build_id=904 version={base + 30}.0.0 status=PENDING\n"
    )
    marker = ("VERIFIER_BUILD_MARKER_" + token).encode()
    dynamic_pid = None

    try:
        history_path.write_text(history)
        fstab_path.write_text(f"{source_dir} {target_dir} bind 0 0\n")
        source.write_bytes(original_source + b"\n__attribute__((used)) static const char verifier_build_marker[] = \"" + marker + b"\";\n")
        try:
            binary_path.unlink()
        except FileNotFoundError:
            pass
        try:
            pid_path.unlink()
        except FileNotFoundError:
            pass

        result = subprocess.run(
            [str(script_path)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            timeout=25,
        )
        assert result.returncode == 0, f"rollout.sh failed on valid dynamic inputs:\n{result.stderr}"
        assert target_dir.is_symlink(), "rollout did not create the configured target symlink"
        assert os.readlink(target_dir) == str(source_dir), \
            f"dynamic symlink points to {os.readlink(target_dir)!r}, not {str(source_dir)!r}"
        assert binary_path.is_file() and os.access(binary_path, os.X_OK), \
            "rollout did not create an executable /home/user/bin/worker"
        assert marker in binary_path.read_bytes(), \
            "rollout did not compile the current /home/user/src/worker.cpp"

        dynamic_pid = read_pid(pid_path)
        assert_real_worker(dynamic_pid, expected_version, str(target_dir))
        wait_for_log(source_dir / "app.log", f"{expected_version} RUNNING {config_line}")
        lines = (source_dir / "app.log").read_text().splitlines()
        assert lines == ["existing-dynamic-entry", f"{expected_version} RUNNING {config_line}"], \
            f"deployed worker wrote unexpected log content: {lines}"
    finally:
        stop_process(dynamic_pid or read_pid(pid_path))
        source.write_bytes(original_source)
        history_path.write_bytes(original_history)
        fstab_path.write_bytes(original_fstab)

    # Restore the required final deployment and ensure the script still leaves it active.
    result = subprocess.run(
        [str(script_path)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        timeout=25,
    )
    assert result.returncode == 0, f"rollout.sh failed when restoring the deployment:\n{result.stderr}"
    restored_pid = read_pid(pid_path)
    assert_real_worker(restored_pid, "1.2.0", "/home/user/mnt_target")
    wait_for_log("/home/user/app_data/app.log", "1.2.0 RUNNING MODE=PRODUCTION")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
