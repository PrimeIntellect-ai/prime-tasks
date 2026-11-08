#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import shutil
import stat
import subprocess
import tempfile
import time


def git(repo, *args):
    result = subprocess.run(
        ["git", "-C", repo, *args],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return result.stdout.strip()


def wait_for(predicate, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            value = predicate()
            if value:
                return value
        except (OSError, ValueError):
            pass
        time.sleep(0.1)
    return None


def read_pid():
    with open("/home/user/daemon.pid", "r") as f:
        value = f.read().strip()
    return int(value) if value.isdigit() and int(value) > 0 else None


def test_critical_dates_extracted():
    log_path = "/home/user/old_crash.log"
    out_path = "/home/user/critical_dates.txt"

    assert os.path.isfile(log_path), f"Source log file {log_path} is missing."
    assert os.path.isfile(out_path), f"Output file {out_path} is missing."

    expected_dates = []
    with open(log_path, "r") as f:
        for line in f:
            if "[CRITICAL FATAL ERROR]" in line:
                parts = line.split()
                if parts:
                    expected_dates.append(parts[0])

    with open(out_path, "r") as f:
        actual_dates = [line.strip() for line in f if line.strip()]

    assert actual_dates == expected_dates, (
        f"Contents of {out_path} do not match expected timestamps. "
        f"Expected {expected_dates}, got {actual_dates}."
    )


def test_deploy_git_is_bare_repo():
    repo_path = "/home/user/deploy.git"
    assert os.path.isdir(repo_path), f"Deploy repository {repo_path} does not exist."
    try:
        result = subprocess.run(
            ["git", "-C", repo_path, "rev-parse", "--is-bare-repository"],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert result.stdout.strip() == "true", f"{repo_path} is not a bare git repository."
    except subprocess.CalledProcessError:
        raise AssertionError(f"Failed to verify if {repo_path} is a bare git repository.")


def test_post_receive_hook_executable():
    hook_path = "/home/user/deploy.git/hooks/post-receive"
    assert os.path.isfile(hook_path), f"Hook file {hook_path} does not exist."
    st = os.stat(hook_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Hook file {hook_path} is not executable."



def test_daemon_repo_remote_configured():
    repo_path = "/home/user/daemon_repo"
    try:
        result = subprocess.run(
            ["git", "-C", repo_path, "remote", "-v"],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        remotes = result.stdout
        assert "deploy" in remotes and "/home/user/deploy.git" in remotes, (
            "The 'deploy' remote is not correctly configured in /home/user/daemon_repo."
        )
    except subprocess.CalledProcessError:
        raise AssertionError(f"Failed to check git remotes in {repo_path}.")


def test_daemon_build_directory_and_executable():
    build_dir = "/home/user/daemon_build"
    daemon_exec = os.path.join(build_dir, "daemon")
    assert os.path.isdir(build_dir), f"Build directory {build_dir} does not exist."
    assert os.path.isfile(daemon_exec), f"Compiled daemon executable {daemon_exec} does not exist."
    st = os.stat(daemon_exec)
    assert bool(st.st_mode & stat.S_IXUSR), f"Daemon file {daemon_exec} is not executable."


def test_daemon_pid_file():
    pid_file = "/home/user/daemon.pid"
    assert os.path.isfile(pid_file), f"PID file {pid_file} does not exist. The daemon may not have started successfully."
    with open(pid_file, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid numeric PID (found: {pid_str})."
    pid = int(pid_str)
    assert pid > 0, f"PID {pid} is invalid."
    try:
        os.kill(pid, 0)
    except OSError:
        raise AssertionError(f"Process with PID {pid} from {pid_file} is not running.")


def test_daemon_log_file():
    log_file = "/home/user/daemon.log"
    assert os.path.isfile(log_file), f"Log file {log_file} does not exist. The daemon may not have started successfully."
    with open(log_file, "r") as f:
        content = f.read().strip()
    assert len(content) > 0, f"Log file {log_file} is empty."


def test_fix_is_committed_and_was_pushed():
    source_repo = "/home/user/daemon_repo"
    deploy_repo = "/home/user/deploy.git"

    local_master = git(source_repo, "rev-parse", "refs/heads/master")
    deployed_master = git(deploy_repo, "rev-parse", "refs/heads/master")
    assert local_master == deployed_master, (
        "The local master commit was not pushed to deploy.git as its master branch."
    )

    assert git(source_repo, "remote", "get-url", "deploy") == "/home/user/deploy.git"
    commit_count = int(git(source_repo, "rev-list", "--count", "master"))
    assert commit_count >= 2, "The daemon fix was not committed after the initial broken commit."

    root_commit = git(source_repo, "rev-list", "--max-parents=0", "master").splitlines()[0]
    diff = git(source_repo, "diff", root_commit, "master", "--", "daemon.c")
    assert diff.strip(), "The committed daemon.c is unchanged from the initial broken version."


def test_committed_daemon_source_runs_successfully():
    deploy_repo = "/home/user/deploy.git"
    source = subprocess.run(
        ["git", "--git-dir", deploy_repo, "show", "refs/heads/master:daemon.c"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    ).stdout

    with tempfile.TemporaryDirectory(prefix="daemon-source-test-") as td:
        src = os.path.join(td, "daemon.c")
        exe = os.path.join(td, "daemon")
        with open(src, "wb") as f:
            f.write(source)
        subprocess.run(["gcc", src, "-o", exe], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        os.chmod(td, 0o755)
        os.chmod(exe, 0o755)

        for path in ("/home/user/daemon.pid", "/home/user/daemon.log"):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        account = pwd.getpwnam("user")
        def demote():
            os.setgid(account.pw_gid)
            os.setuid(account.pw_uid)

        proc = subprocess.Popen(
            [exe], cwd=td, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            preexec_fn=demote
        )
        try:
            pid = wait_for(read_pid)
            assert pid == proc.pid, "The compiled committed daemon did not write its own PID."
            assert wait_for(lambda: os.path.isfile("/home/user/daemon.log")), (
                "The compiled committed daemon did not create daemon.log."
            )
            with open("/home/user/daemon.log", "r") as f:
                assert f.read().strip() == "Daemon started successfully"
            assert proc.poll() is None, "The compiled committed daemon exited unexpectedly."
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=2)


def test_post_receive_hook_performs_fresh_deployment():
    hook = "/home/user/deploy.git/hooks/post-receive"
    deploy_repo = "/home/user/deploy.git"
    build_dir = "/home/user/daemon_build"
    daemon_exec = os.path.join(build_dir, "daemon")
    build_source = os.path.join(build_dir, "daemon.c")

    with open(hook, "r", errors="replace") as f:
        hook_text = f.read()
    assert hook_text.strip(), "The post-receive hook is empty."
    assert "/home/user/daemon_build" in hook_text, "The hook does not target daemon_build."
    assert re.search(r"\bgcc\b", hook_text), "The hook does not invoke gcc."
    assert "daemon.c" in hook_text, "The hook does not compile daemon.c."
    assert re.search(r"\bcheckout\b", hook_text), "The hook does not check out deployed code."

    old_pid = None
    try:
        old_pid = read_pid()
    except (OSError, ValueError):
        pass

    shutil.rmtree(build_dir, ignore_errors=True)
    for path in ("/home/user/daemon.pid", "/home/user/daemon.log"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    head = git(deploy_repo, "rev-parse", "refs/heads/master")
    parent = git(deploy_repo, "rev-parse", "refs/heads/master^")
    hook_input = f"{parent} {head} refs/heads/master\n"
    result = subprocess.run(
        ["runuser", "-u", "user", "--", hook],
        cwd=deploy_repo,
        input=hook_input,
        text=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, f"post-receive hook failed: {result.stderr}"

    assert wait_for(lambda: os.path.isfile(daemon_exec)), (
        "Executing the post-receive hook did not build daemon_build/daemon."
    )
    assert os.path.isfile(build_source), "The hook did not check out daemon.c into daemon_build."
    assert os.access(daemon_exec, os.X_OK), "The freshly built daemon is not executable."

    deployed_source = subprocess.run(
        ["git", "--git-dir", deploy_repo, "show", "refs/heads/master:daemon.c"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    ).stdout
    with open(build_source, "rb") as f:
        assert f.read() == deployed_source, (
            "daemon_build/daemon.c is not the daemon.c from the pushed master commit."
        )

    pid = wait_for(read_pid)
    assert pid is not None, "The hook's daemon did not write a valid PID file."
    if old_pid is not None:
        assert pid != old_pid, "No newly launched daemon replaced the pre-existing PID file."
    try:
        os.kill(pid, 0)
    except OSError:
        raise AssertionError("The daemon launched by the hook is not running.")

    exe_link = os.path.realpath(f"/proc/{pid}/exe")
    assert exe_link == os.path.realpath(daemon_exec), (
        f"PID {pid} is not the daemon executable built by the hook (found {exe_link})."
    )
    with open(f"/proc/{pid}/status", "r") as f:
        status = f.read()
    uid_match = re.search(r"^Uid:\s+(\d+)", status, re.MULTILINE)
    assert uid_match and int(uid_match.group(1)) == pwd.getpwnam("user").pw_uid, (
        "The deployed daemon is not running as user."
    )

    assert wait_for(lambda: os.path.isfile("/home/user/daemon.log")), (
        "The daemon launched by the hook did not create daemon.log."
    )
    with open("/home/user/daemon.log", "r") as f:
        assert f.read().strip() == "Daemon started successfully", (
            "The deployed daemon did not write the required success message."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
