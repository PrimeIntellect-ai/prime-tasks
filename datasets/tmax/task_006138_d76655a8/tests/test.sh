#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import stat
import subprocess
import time

BASE_DIR = "/home/user/microservice"
V1_DIR = os.path.join(BASE_DIR, "releases/v1")
V2_DIR = os.path.join(BASE_DIR, "releases/v2")
SHARED_DIR = os.path.join(BASE_DIR, "shared")
CURRENT_LINK = os.path.join(BASE_DIR, "current")
DEPLOY_SCRIPT = os.path.join(BASE_DIR, "deploy.sh")
APP_LOG = os.path.join(SHARED_DIR, "app.log")
DEPLOY_LOG = os.path.join(SHARED_DIR, "deploy.log")


def read_lines(path):
    if not os.path.isfile(path):
        return []
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def wait_for_count(path, line, count, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if read_lines(path).count(line) >= count:
            return
        time.sleep(0.03)
    raise AssertionError(f"Did not observe {count} occurrences of {line!r} in {path}")


def worker_pids_for(directory):
    result = []
    wanted = os.path.realpath(directory)
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
            cwd = os.path.realpath(os.readlink(f"/proc/{pid}/cwd"))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if "worker.sh" in cmdline and cwd == wanted:
            result.append(pid)
    return result


def stop_pids(pids):
    pids = set(pids)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 3
    while pids and time.monotonic() < deadline:
        pids = {pid for pid in pids if os.path.exists(f"/proc/{pid}")}
        time.sleep(0.05)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def assert_bash_script(path):
    assert os.path.isfile(path), f"Script {path} does not exist."
    assert os.access(path, os.X_OK), f"Script {path} is not executable."
    with open(path, "rb") as f:
        first_line = f.readline().decode(errors="replace").strip()
    assert first_line.startswith("#!") and "bash" in first_line, f"{path} is not an executable Bash script."


def test_directories_exist():
    for d in [V1_DIR, V2_DIR, SHARED_DIR]:
        assert os.path.isdir(d), f"Directory {d} does not exist."


def test_symlink_points_to_v2():
    assert os.path.islink(CURRENT_LINK), f"{CURRENT_LINK} is not a symlink."
    target = os.readlink(CURRENT_LINK)
    abs_target = os.path.abspath(os.path.join(BASE_DIR, target))
    assert abs_target == V2_DIR, f"Symlink {CURRENT_LINK} points to {abs_target}, expected {V2_DIR}."


def test_config_files_and_permissions():
    configs = [
        (os.path.join(V1_DIR, "config.ini"), "MODE=blue"),
        (os.path.join(V2_DIR, "config.ini"), "MODE=green")
    ]
    for path, expected_content in configs:
        assert os.path.isfile(path), f"Config file {path} does not exist."
        with open(path, "r") as f:
            content = f.read().strip()
        assert content == expected_content, f"Config file {path} content is '{content}', expected '{expected_content}'."
        mode = stat.S_IMODE(os.stat(path).st_mode)
        assert mode == 0o400, f"Permissions for {path} are {oct(mode)}, expected 0o400."


def test_worker_scripts_executable():
    for d in [V1_DIR, V2_DIR]:
        script_path = os.path.join(d, "worker.sh")
        assert os.path.isfile(script_path), f"Worker script {script_path} does not exist."
        assert os.access(script_path, os.X_OK), f"Worker script {script_path} is not executable."
        assert_bash_script(script_path)


def test_deploy_log():
    assert os.path.isfile(DEPLOY_LOG), f"Deploy log {DEPLOY_LOG} does not exist."
    with open(DEPLOY_LOG, "r") as f:
        content = f.read().strip()
    assert content == "Deployment of v2 successful", f"Deploy log content is incorrect: '{content}'"


def test_app_log_sequence():
    assert os.path.isfile(APP_LOG), f"App log {APP_LOG} does not exist."
    lines = read_lines(APP_LOG)
    assert "Heartbeat: blue" in lines, "Missing 'Heartbeat: blue' in app.log."
    assert "Shutting down gracefully" in lines, "Missing 'Shutting down gracefully' in app.log."
    assert "Heartbeat: green" in lines, "Missing 'Heartbeat: green' in app.log."

    blue_indices = [i for i, line in enumerate(lines) if line == "Heartbeat: blue"]
    shutdown_indices = [i for i, line in enumerate(lines) if line == "Shutting down gracefully"]
    green_indices = [i for i, line in enumerate(lines) if line == "Heartbeat: green"]
    assert green_indices
    assert len(shutdown_indices) == 1, "Expected exactly one 'Shutting down gracefully' message."
    first_blue = blue_indices[0]
    shutdown = shutdown_indices[0]
    assert first_blue < shutdown, "'Heartbeat: blue' must appear before 'Shutting down gracefully'."


def exercise_worker(directory, token):
    config = os.path.join(directory, "config.ini")
    worker = os.path.join(directory, "worker.sh")
    with open(config, "r") as f:
        original = f.read()
    proc = None
    try:
        # A distinct runtime value ensures the worker really reads its own config.
        with open(config, "w") as f:
            f.write(f"MODE={token}\n")
        with open(APP_LOG, "w"):
            pass

        proc = subprocess.Popen(
            [worker], cwd="/tmp", stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True
        )
        heartbeat = f"Heartbeat: {token}"
        wait_for_count(APP_LOG, heartbeat, 1, 2.0)
        first_seen = time.monotonic()
        wait_for_count(APP_LOG, heartbeat, 2, 2.0)
        second_seen = time.monotonic()
        assert second_seen - first_seen >= 0.65, "worker.sh does not sleep approximately one second between heartbeats."

        proc.send_signal(signal.SIGTERM)
        proc.wait(timeout=3)
        assert proc.returncode == 0, "worker.sh did not exit successfully after SIGTERM."
        lines = read_lines(APP_LOG)
        assert lines.count("Shutting down gracefully") == 1, "worker.sh did not log exactly one graceful shutdown on SIGTERM."
    finally:
        with open(config, "w") as f:
            f.write(original)
        os.chmod(config, 0o400)
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=2)


def test_workers_and_deployment_execute_correctly():
    assert_bash_script(DEPLOY_SCRIPT)

    exercise_worker(V1_DIR, "runtime_blue_check")
    exercise_worker(V2_DIR, "runtime_green_check")

    # Recreate the state immediately before deployment and execute deploy.sh.
    replacement = os.path.join(BASE_DIR, ".current-verifier")
    try:
        os.unlink(replacement)
    except FileNotFoundError:
        pass
    os.symlink(V1_DIR, replacement)
    os.replace(replacement, CURRENT_LINK)
    with open(APP_LOG, "w"):
        pass
    try:
        os.unlink(DEPLOY_LOG)
    except FileNotFoundError:
        pass

    old = subprocess.Popen(
        ["./worker.sh"], cwd=CURRENT_LINK, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True
    )
    deploy = None
    try:
        wait_for_count(APP_LOG, "Heartbeat: blue", 2, 3.5)
        deploy = subprocess.Popen(
            [DEPLOY_SCRIPT], cwd=BASE_DIR, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True
        )

        deadline = time.monotonic() + 8
        while deploy.poll() is None and time.monotonic() < deadline:
            # An atomic replacement must never expose a missing/non-symlink current path.
            assert os.path.islink(CURRENT_LINK), "current ceased to be a symlink during deployment."
            resolved = os.path.realpath(CURRENT_LINK)
            assert resolved in (V1_DIR, V2_DIR), f"current had an invalid target during deployment: {resolved}"
            time.sleep(0.002)
        if deploy.poll() is None:
            os.killpg(deploy.pid, signal.SIGKILL)
            deploy.wait(timeout=2)
            raise AssertionError("deploy.sh did not complete; it must wait only for the old worker.")
        assert deploy.returncode == 0, f"deploy.sh exited with status {deploy.returncode}."

        assert os.path.islink(CURRENT_LINK), "deploy.sh did not leave current as a symlink."
        assert os.path.realpath(CURRENT_LINK) == V2_DIR, "deploy.sh did not switch current to v2."

        old.wait(timeout=3)
        assert old.returncode == 0, "The old v1 worker was not gracefully terminated by deploy.sh."
        wait_for_count(APP_LOG, "Heartbeat: green", 1, 3)

        lines = read_lines(APP_LOG)
        assert lines.count("Heartbeat: blue") >= 2, "The initial v1 worker did not run for at least two heartbeats."
        assert lines.count("Shutting down gracefully") == 1, "Deployment did not gracefully terminate exactly the old worker."
        assert lines.index("Heartbeat: green") < lines.index("Shutting down gracefully"), "v2 was not started before v1 was terminated."

        new_pids = worker_pids_for(V2_DIR)
        assert new_pids, "deploy.sh did not start a live v2 worker from the updated current directory."

        assert os.path.isfile(DEPLOY_LOG), "deploy.sh did not create deploy.log."
        with open(DEPLOY_LOG, "r") as f:
            assert f.read().strip() == "Deployment of v2 successful"
    finally:
        if deploy is not None and deploy.poll() is None:
            try:
                os.killpg(deploy.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        if old.poll() is None:
            try:
                os.killpg(old.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        stop_pids(worker_pids_for(V1_DIR) + worker_pids_for(V2_DIR))


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
