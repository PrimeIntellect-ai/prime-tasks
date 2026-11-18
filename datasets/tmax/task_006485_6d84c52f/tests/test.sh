#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import py_compile
import secrets
import shutil
import subprocess
import tarfile
import tempfile
import time

import pytest

HOME = "/home/user"
CI_DIR = os.path.join(HOME, "ci_builds")
ACTIVE_DIR = os.path.join(HOME, "active_deployment")
CONF_FILE = os.path.join(HOME, "deployment_network.conf")
PID_FILE = os.path.join(HOME, "watcher.pid")
DAEMON_SCRIPT = os.path.join(HOME, "watch_and_deploy.py")
CI_SCRIPT = os.path.join(HOME, "mock_ci.py")


def read_pid():
    assert os.path.isfile(PID_FILE), f"PID file {PID_FILE} does not exist."
    with open(PID_FILE, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file {PID_FILE} does not contain a valid integer PID."
    return int(pid_str)


def assert_daemon_process(pid):
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} (from {PID_FILE}) is not running.")

    cmdline_path = f"/proc/{pid}/cmdline"
    assert os.path.isfile(cmdline_path), f"Cannot inspect command line for PID {pid}."
    with open(cmdline_path, "rb") as f:
        argv = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
    daemon_realpath = os.path.realpath(DAEMON_SCRIPT)
    assert any(os.path.realpath(arg) == daemon_realpath for arg in argv), (
        f"PID {pid} is not running {DAEMON_SCRIPT}; command line was {argv!r}."
    )


def wait_until(predicate, timeout=12):
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            if predicate():
                return
        except (OSError, AssertionError) as exc:
            last_error = exc
        time.sleep(0.1)
    if last_error:
        raise AssertionError(f"Condition was not met before timeout: {last_error}")
    raise AssertionError("Condition was not met before timeout")


def exact_conf(filename):
    return [
        "ACTIVE_DIR=/home/user/active_deployment",
        f"LAST_DEPLOYED={filename}",
        "STATUS=live",
    ]


def test_00_scripts_and_live_pipeline_behavior():
    for script in (DAEMON_SCRIPT, CI_SCRIPT):
        assert os.path.isfile(script), f"Required Python script {script} does not exist."
        assert not os.path.islink(script), f"Required Python script {script} must be a real file."
        py_compile.compile(script, doraise=True)

    assert os.path.isdir(CI_DIR), f"Directory {CI_DIR} does not exist."
    assert os.path.isdir(ACTIVE_DIR), f"Directory {ACTIVE_DIR} does not exist."

    pid = read_pid()
    assert_daemon_process(pid)

    # Submit a verifier-generated archive whose names and contents cannot be
    # satisfied by merely pre-creating the requested final Beta filesystem.
    token = secrets.token_hex(16)
    archive_name = f"verifier_{token}.tar"
    archive_path = os.path.join(CI_DIR, archive_name)
    expected_index = f"dynamic deployment {token}"
    expected_probe = f"probe {secrets.token_hex(12)}"

    stale_dir = os.path.join(ACTIVE_DIR, "stale", "nested")
    os.makedirs(stale_dir, exist_ok=True)
    with open(os.path.join(stale_dir, "must_be_removed.txt"), "w") as f:
        f.write("old deployment")

    with tempfile.TemporaryDirectory() as build_dir:
        with open(os.path.join(build_dir, "index.html"), "w") as f:
            f.write(expected_index)
        os.makedirs(os.path.join(build_dir, "assets"))
        with open(os.path.join(build_dir, "assets", "probe.txt"), "w") as f:
            f.write(expected_probe)
        staged_tar = os.path.join(build_dir, "artifact.tar")
        with tarfile.open(staged_tar, "w") as tf:
            tf.add(os.path.join(build_dir, "index.html"), arcname="index.html")
            tf.add(os.path.join(build_dir, "assets", "probe.txt"), arcname="assets/probe.txt")
        shutil.copyfile(staged_tar, archive_path)

    def dynamic_deployment_complete():
        if os.path.exists(archive_path) or os.path.exists(os.path.join(ACTIVE_DIR, "stale")):
            return False
        with open(os.path.join(ACTIVE_DIR, "index.html")) as f:
            if f.read() != expected_index:
                return False
        with open(os.path.join(ACTIVE_DIR, "assets", "probe.txt")) as f:
            if f.read() != expected_probe:
                return False
        with open(CONF_FILE) as f:
            return f.read().splitlines() == exact_conf(archive_name)

    wait_until(dynamic_deployment_complete)
    assert_daemon_process(pid)

    # Execute the submitted CI program itself. Observe Alpha while it runs, then
    # require the daemon to consume its final Beta artifact and restore the
    # instruction's specified final state.
    with tempfile.TemporaryDirectory() as work_dir:
        proc = subprocess.Popen(
            ["python3", CI_SCRIPT],
            cwd=work_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        saw_alpha = False
        deadline = time.monotonic() + 12
        while proc.poll() is None and time.monotonic() < deadline:
            if os.path.exists(os.path.join(CI_DIR, "build_alpha.tar")):
                saw_alpha = True
            try:
                with open(CONF_FILE) as f:
                    if f.read().splitlines() == exact_conf("build_alpha.tar"):
                        saw_alpha = True
            except OSError:
                pass
            time.sleep(0.05)
        if proc.poll() is None:
            proc.kill()
            stdout, stderr = proc.communicate()
            pytest.fail(f"{CI_SCRIPT} did not finish in time. stdout={stdout!r}, stderr={stderr!r}")
        stdout, stderr = proc.communicate()
        assert proc.returncode == 0, (
            f"{CI_SCRIPT} exited with {proc.returncode}. stdout={stdout!r}, stderr={stderr!r}"
        )
        assert saw_alpha, f"{CI_SCRIPT} did not create and publish build_alpha.tar."

    def beta_deployment_complete():
        if os.listdir(CI_DIR):
            return False
        with open(os.path.join(ACTIVE_DIR, "index.html")) as f:
            if f.read().strip() != "Build Version Beta":
                return False
        with open(CONF_FILE) as f:
            return f.read().splitlines() == exact_conf("build_beta.tar")

    wait_until(beta_deployment_complete)
    assert_daemon_process(pid)


def test_daemon_running():
    """Check that the daemon PID is saved and the process is running."""
    pid_file = "/home/user/watcher.pid"
    assert os.path.isfile(pid_file), f"PID file {pid_file} does not exist."

    with open(pid_file, "r") as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid integer PID."
    pid = int(pid_str)

    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} (from {pid_file}) is not running.")


def test_deployment_network_conf():
    """Check the final deployment config file."""
    conf_file = "/home/user/deployment_network.conf"
    assert os.path.isfile(conf_file), f"Config file {conf_file} does not exist."

    with open(conf_file, "r") as f:
        content = f.read()

    expected_lines = [
        "ACTIVE_DIR=/home/user/active_deployment",
        "LAST_DEPLOYED=build_beta.tar",
        "STATUS=live"
    ]

    for line in expected_lines:
        assert line in content, f"Expected line '{line}' not found in {conf_file}."


def test_active_deployment_content():
    """Check that the active deployment contains the final build."""
    index_file = "/home/user/active_deployment/index.html"
    assert os.path.isfile(index_file), f"Deployed file {index_file} does not exist."

    with open(index_file, "r") as f:
        content = f.read().strip()

    assert content == "Build Version Beta", f"Expected 'Build Version Beta' in {index_file}, found '{content}'."


def test_ci_builds_empty():
    """Check that the ci_builds directory is clean."""
    ci_builds_dir = "/home/user/ci_builds"
    assert os.path.isdir(ci_builds_dir), f"Directory {ci_builds_dir} does not exist."

    contents = os.listdir(ci_builds_dir)
    assert len(contents) == 0, f"Directory {ci_builds_dir} is not empty. Found: {contents}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
