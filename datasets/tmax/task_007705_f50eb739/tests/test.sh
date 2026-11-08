#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shlex
import socket
import stat
import subprocess
import tempfile
import time
import uuid


def run_cmd(cmd, cwd=None):
    return subprocess.run(cmd, shell=True, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def test_authorized_deployers_file():
    filepath = "/home/user/authorized_deployers.txt"
    assert os.path.isfile(filepath), f"{filepath} does not exist."
    with open(filepath, "r") as f:
        content = f.read()
    assert "alice@example.com" in content, "alice@example.com not in authorized_deployers.txt"
    assert "bob@example.com" in content, "bob@example.com not in authorized_deployers.txt"


def test_daemon_artifacts_and_unit():
    source = "/home/user/deploy_daemon.c"
    binary = "/home/user/deploy_daemon"
    unit = "/home/user/.config/systemd/user/deploy-daemon.service"
    hook = "/home/user/deploy_repo.git/hooks/post-receive"

    assert os.path.isfile(source), f"{source} does not exist."
    syntax = run_cmd(f"gcc -fsyntax-only {shlex.quote(source)}")
    assert syntax.returncode == 0, f"deploy_daemon.c is not valid C: {syntax.stderr}"

    assert os.path.isfile(binary), f"{binary} does not exist."
    assert os.access(binary, os.X_OK), f"{binary} is not executable."
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{binary} is not a compiled ELF executable."

    assert os.path.isfile(unit), f"{unit} does not exist."
    with open(unit, "r") as f:
        unit_lines = f.readlines()
    exec_values = [line.strip().split("=", 1)[1] for line in unit_lines if line.strip().startswith("ExecStart=") and line.strip() != "ExecStart="]
    assert exec_values, "The service unit has no ExecStart command."
    try:
        executable = shlex.split(exec_values[-1])[0]
    except (ValueError, IndexError) as exc:
        raise AssertionError(f"Invalid ExecStart command: {exc}")
    assert executable == binary, "The service unit does not execute /home/user/deploy_daemon."

    assert os.path.isfile(hook), f"{hook} does not exist."
    assert os.access(hook, os.X_OK), f"{hook} is not executable."


def test_systemd_service_active_and_runs_binary():
    res = run_cmd("systemctl --user is-active deploy-daemon.service")
    assert res.stdout.strip() == "active", "deploy-daemon.service is not active."

    pid_res = run_cmd("systemctl --user show deploy-daemon.service -p MainPID --value")
    assert pid_res.returncode == 0 and pid_res.stdout.strip().isdigit(), "Could not determine the service MainPID."
    pid = int(pid_res.stdout.strip())
    assert pid > 0, "deploy-daemon.service has no running MainPID."
    actual_exe = os.path.realpath(f"/proc/{pid}/exe")
    assert actual_exe == "/home/user/deploy_daemon", f"The active service runs {actual_exe}, not deploy_daemon."


def test_socket_exists_and_is_owned_by_daemon():
    socket_path = "/home/user/deploy.sock"
    assert os.path.exists(socket_path), f"Unix socket {socket_path} does not exist."
    mode = os.stat(socket_path).st_mode
    assert stat.S_ISSOCK(mode), f"{socket_path} is not a socket."

    pid_res = run_cmd("systemctl --user show deploy-daemon.service -p MainPID --value")
    assert pid_res.stdout.strip().isdigit(), "Could not determine the daemon PID."
    pid = int(pid_res.stdout.strip())
    inode = os.stat(socket_path).st_ino
    owned = False
    for fd in os.listdir(f"/proc/{pid}/fd"):
        try:
            if os.readlink(f"/proc/{pid}/fd/{fd}") == f"socket:[{inode}]":
                owned = True
                break
        except FileNotFoundError:
            pass
    assert owned, "The running deploy_daemon process does not own the listening Unix socket."


def create_unreferenced_commit(repo, email, filename, contents):
    env = os.environ.copy()
    env.update({
        "GIT_AUTHOR_NAME": "Verifier",
        "GIT_AUTHOR_EMAIL": email,
        "GIT_COMMITTER_NAME": "Verifier",
        "GIT_COMMITTER_EMAIL": email,
    })
    with tempfile.TemporaryDirectory() as td:
        index = os.path.join(td, "index")
        env["GIT_INDEX_FILE"] = index

        blob = subprocess.run(
            ["git", "--git-dir", repo, "hash-object", "-w", "--stdin"],
            input=contents,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
        )
        assert blob.returncode == 0, blob.stderr
        blob_hash = blob.stdout.strip()

        empty = subprocess.run(["git", "--git-dir", repo, "read-tree", "--empty"], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert empty.returncode == 0, empty.stderr
        add = subprocess.run(
            ["git", "--git-dir", repo, "update-index", "--add", "--cacheinfo", f"100644,{blob_hash},{filename}"],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert add.returncode == 0, add.stderr
        tree = subprocess.run(["git", "--git-dir", repo, "write-tree"], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert tree.returncode == 0, tree.stderr
        commit = subprocess.run(
            ["git", "--git-dir", repo, "commit-tree", tree.stdout.strip()],
            input=f"Verifier probe {uuid.uuid4()}\n",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert commit.returncode == 0, commit.stderr
        return commit.stdout.strip()


def send_commit(commit_hash):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(3)
        client.connect("/home/user/deploy.sock")
        client.sendall((commit_hash + "\n").encode())


def wait_for_log_line(expected, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with open("/home/user/deploy.log", "r") as f:
                if expected in f.read().splitlines():
                    return
        except FileNotFoundError:
            pass
        time.sleep(0.1)
    raise AssertionError(f"Daemon did not write expected log line: {expected}")


def test_daemon_directly_authorizes_and_deploys():
    repo = "/home/user/deploy_repo.git"
    assert os.path.isdir(repo), f"Bare repo {repo} does not exist."
    marker = f"daemon-probe-{uuid.uuid4().hex}.txt"
    authorized_contents = f"authorized-{uuid.uuid4().hex}\n"
    denied_contents = f"denied-{uuid.uuid4().hex}\n"

    authorized_hash = create_unreferenced_commit(repo, "bob@example.com", marker, authorized_contents)
    send_commit(authorized_hash)
    wait_for_log_line(f"SUCCESS: {authorized_hash} by bob@example.com")

    deployed = os.path.join("/home/user/live_site", marker)
    deadline = time.time() + 5
    while time.time() < deadline and not os.path.isfile(deployed):
        time.sleep(0.1)
    assert os.path.isfile(deployed), "The C daemon did not deploy a commit sent directly to its socket."
    with open(deployed, "r") as f:
        assert f.read() == authorized_contents, "Direct authorized deployment content mismatch."

    denied_hash = create_unreferenced_commit(repo, "direct-probe@invalid.example", marker, denied_contents)
    send_commit(denied_hash)
    wait_for_log_line(f"DENIED: {denied_hash} by direct-probe@invalid.example")
    with open(deployed, "r") as f:
        assert f.read() == authorized_contents, "A directly submitted unauthorized commit was deployed."


def test_deployment_workflow():
    repo_path = "/home/user/deploy_repo.git"
    assert os.path.isdir(repo_path), f"Bare repo {repo_path} does not exist."

    live_site = "/home/user/live_site"
    os.makedirs(live_site, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmpdir:
        clone_res = run_cmd(f"git clone {repo_path} {tmpdir}")
        assert clone_res.returncode == 0, f"Failed to clone repo: {clone_res.stderr}"

        run_cmd('git config user.email "alice@example.com"', cwd=tmpdir)
        run_cmd('git config user.name "Alice"', cwd=tmpdir)

        with open(os.path.join(tmpdir, "index.html"), "w") as f:
            f.write("<html>Deploy1</html>")

        run_cmd("git add index.html", cwd=tmpdir)
        run_cmd('git commit -m "Authorized deploy"', cwd=tmpdir)
        hash1 = run_cmd("git rev-parse HEAD", cwd=tmpdir).stdout.strip()

        push_res = run_cmd("git push origin master", cwd=tmpdir)
        assert push_res.returncode == 0, f"Failed to push authorized commit: {push_res.stderr}"
        time.sleep(2)

        log_path = "/home/user/deploy.log"
        assert os.path.isfile(log_path), f"Log file {log_path} does not exist."
        with open(log_path, "r") as f:
            log_content = f.read()
        assert f"SUCCESS: {hash1} by alice@example.com" in log_content, "Authorized deploy not logged as SUCCESS."

        deployed_file = os.path.join(live_site, "index.html")
        assert os.path.isfile(deployed_file), "Deployed file not found in live_site."
        with open(deployed_file, "r") as f:
            assert f.read().strip() == "<html>Deploy1</html>", "Deployed file content mismatch."

        run_cmd('git config user.email "mallory@evil.com"', cwd=tmpdir)
        run_cmd('git config user.name "Mallory"', cwd=tmpdir)
        with open(os.path.join(tmpdir, "index.html"), "w") as f:
            f.write("<html>Hacked</html>")

        run_cmd("git add index.html", cwd=tmpdir)
        run_cmd('git commit -m "Unauthorized deploy"', cwd=tmpdir)
        hash2 = run_cmd("git rev-parse HEAD", cwd=tmpdir).stdout.strip()

        push_res = run_cmd("git push origin master", cwd=tmpdir)
        assert push_res.returncode == 0, f"Failed to push unauthorized commit: {push_res.stderr}"
        time.sleep(2)

        with open(log_path, "r") as f:
            log_content = f.read()
        assert f"DENIED: {hash2} by mallory@evil.com" in log_content, "Unauthorized deploy not logged as DENIED."
        with open(deployed_file, "r") as f:
            assert f.read().strip() == "<html>Deploy1</html>", "Unauthorized deploy overwrote the live site."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
