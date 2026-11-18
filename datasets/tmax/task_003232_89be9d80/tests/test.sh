#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import tempfile
import time
import uuid


def git(*args, cwd=None):
    return subprocess.run(
        ["git", "-c", "safe.directory=*", *args],
        cwd=cwd,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    ).stdout.strip()


def test_01_post_receive_hook_exists_and_executable():
    hook_path = "/home/user/monitor.git/hooks/post-receive"
    assert os.path.isfile(hook_path), f"The post-receive hook was not found at {hook_path}."
    assert os.access(hook_path, os.X_OK), f"The post-receive hook at {hook_path} is not executable."
    assert stat.S_ISREG(os.lstat(hook_path).st_mode), f"The hook at {hook_path} is not a regular file."


def test_02_monitor_binary_exists_and_permissions():
    binary_path = "/home/user/bin/monitor"
    assert os.path.isfile(binary_path), f"The compiled binary was not found at {binary_path}."

    st = os.stat(binary_path)
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o755, f"The binary at {binary_path} has permissions {oct(permissions)}, expected 0o755."


def test_03_alerts_log_content():
    pid_file = "/home/user/target.pid"
    assert os.path.isfile(pid_file), f"The PID file {pid_file} is missing."

    with open(pid_file, "r") as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), f"The PID file {pid_file} does not contain a valid integer."

    proc_comm_file = f"/proc/{pid_str}/comm"
    assert os.path.isfile(proc_comm_file), f"The target process (PID {pid_str}) is no longer running."

    with open(proc_comm_file, "r") as f:
        target_name = f.read().strip()

    expected_log = f"ALERT: Process {target_name} (PID {pid_str}) detected"

    log_file = "/home/user/alerts.log"
    assert os.path.isfile(log_file), f"The alerts log file {log_file} was not created."

    with open(log_file, "r") as f:
        log_content = f.read()

    assert expected_log in log_content, f"The expected log entry '{expected_log}' was not found in {log_file}."


def test_04_source_was_committed_and_pushed():
    workspace = "/home/user/workspace"
    bare = "/home/user/monitor.git"
    assert os.path.isdir(os.path.join(workspace, ".git")), f"{workspace} is not a Git clone."
    assert git("-C", workspace, "rev-parse", "--is-inside-work-tree") == "true"

    head = git("-C", workspace, "rev-parse", "HEAD")
    bare_master = git("--git-dir", bare, "rev-parse", "refs/heads/master")
    assert head == bare_master, "The workspace HEAD was not pushed to the bare repository's master branch."

    tracked = git("-C", workspace, "ls-files", "--error-unmatch", "monitor.cpp")
    assert tracked == "monitor.cpp", "monitor.cpp is not tracked in the workspace commit."
    assert git("-C", workspace, "status", "--porcelain", "--", "monitor.cpp") == "", "monitor.cpp has uncommitted changes."

    remote_master = git("-C", workspace, "ls-remote", "origin", "refs/heads/master").split()
    assert remote_master and remote_master[0] == head, "The clone's origin/master does not contain the workspace commit."

    workspace_source = open(os.path.join(workspace, "monitor.cpp"), "rb").read()
    pushed_source = subprocess.run(
        ["git", "-c", "safe.directory=*", "--git-dir", bare, "show", "master:monitor.cpp"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout
    assert workspace_source == pushed_source, "The pushed monitor.cpp differs from the committed workspace source."


def test_05_real_push_triggers_checkout_and_compilation():
    bare = "/home/user/monitor.git"
    deploy = "/home/user/deploy"
    bindir = "/home/user/bin"
    shutil.rmtree(deploy, ignore_errors=True)
    shutil.rmtree(bindir, ignore_errors=True)

    with tempfile.TemporaryDirectory(prefix="verify-push-") as td:
        clone = os.path.join(td, "clone")
        git("clone", bare, clone)
        git("-C", clone, "config", "user.email", "verifier@example.invalid")
        git("-C", clone, "config", "user.name", "Verifier")
        probe_name = "verifier-probe-" + uuid.uuid4().hex
        with open(os.path.join(clone, probe_name), "w") as f:
            f.write("hook checkout probe\n")
        git("-C", clone, "add", probe_name)
        git("-C", clone, "commit", "-m", "Verifier deployment probe")
        git("-C", clone, "push", "origin", "HEAD:master")

        assert os.path.isdir(deploy), "The post-receive hook did not recreate /home/user/deploy."
        assert os.path.isdir(bindir), "The post-receive hook did not recreate /home/user/bin."
        assert os.path.isfile(os.path.join(deploy, probe_name)), "The pushed work tree was not checked out into /home/user/deploy."

    deployed_source = os.path.join(deploy, "monitor.cpp")
    binary = os.path.join(bindir, "monitor")
    assert os.path.isfile(deployed_source), "The hook did not check out monitor.cpp."
    assert os.path.isfile(binary), "The hook did not produce /home/user/bin/monitor."
    assert stat.S_ISREG(os.lstat(binary).st_mode), "The deployed monitor is not a regular file."
    assert stat.S_IMODE(os.stat(binary).st_mode) == 0o755, "The freshly deployed monitor does not have mode 0755."
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The freshly deployed monitor is not a compiled ELF executable."

    pushed_source = subprocess.run(
        ["git", "-c", "safe.directory=*", "--git-dir", bare, "show", "master:monitor.cpp"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout
    with open(deployed_source, "rb") as f:
        assert f.read() == pushed_source, "The hook did not deploy monitor.cpp from the pushed master branch."


def exercise_monitor(executable):
    pid_path = "/home/user/target.pid"
    log_path = "/home/user/alerts.log"
    old_pid = open(pid_path, "rb").read()
    log_existed = os.path.exists(log_path)
    old_log = open(log_path, "rb").read() if log_existed else b""

    with tempfile.TemporaryDirectory(prefix="monitor-target-") as td:
        target_name = "p" + uuid.uuid4().hex[:10]
        target_exe = os.path.join(td, target_name)
        shutil.copy2("/bin/sleep", target_exe)
        os.chmod(target_exe, 0o755)
        proc = subprocess.Popen([target_exe, "30"])
        try:
            proc_comm = f"/proc/{proc.pid}/comm"
            for _ in range(50):
                if os.path.isfile(proc_comm):
                    break
                time.sleep(0.02)
            with open(proc_comm, "r") as f:
                actual_name = f.read().rstrip()

            with open(pid_path, "w") as f:
                f.write(f"{proc.pid}\n")
            with open(log_path, "wb") as f:
                f.write(b"")

            subprocess.run([executable], check=True, timeout=10)
            expected = f"ALERT: Process {actual_name} (PID {proc.pid}) detected\n".encode()
            with open(log_path, "rb") as f:
                result = f.read()
            assert result == expected, f"Monitor wrote {result!r}, expected exactly {expected!r}."
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
            with open(pid_path, "wb") as f:
                f.write(old_pid)
            if log_existed:
                with open(log_path, "wb") as f:
                    f.write(old_log)
            elif os.path.exists(log_path):
                os.unlink(log_path)


def test_06_deployed_binary_and_cpp_source_implement_monitoring_behavior():
    deployed_binary = "/home/user/bin/monitor"
    exercise_monitor(deployed_binary)

    with tempfile.TemporaryDirectory(prefix="verify-build-") as td:
        rebuilt = os.path.join(td, "monitor-from-source")
        subprocess.run(
            ["g++", "/home/user/deploy/monitor.cpp", "-o", rebuilt],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        exercise_monitor(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
