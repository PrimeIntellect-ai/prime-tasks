#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import shutil
import socket
import subprocess
import time
import uuid

import pytest

USER = pwd.getpwnam("user")


def user_preexec():
    os.setgroups([])
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def run_user(args, **kwargs):
    env = os.environ.copy()
    env.update({"HOME": "/home/user", "USER": "user", "LOGNAME": "user"})
    return subprocess.run(args, env=env, preexec_fn=user_preexec, **kwargs)


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def port_open(port):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.2):
            return True
    except OSError:
        return False


@pytest.fixture(scope="session", autouse=True)
def run_student_script():
    script_path = "/home/user/setup_edge_pipeline.sh"
    assert os.path.isfile(script_path), f"Student script {script_path} not found."
    assert os.access(script_path, os.X_OK), f"Student script {script_path} is not executable."

    for path in [
        "/home/user/iot-device.git",
        "/home/user/workspace",
        "/home/user/iot-active",
        "/home/user/deploy.log",
    ]:
        if os.path.lexists(path):
            remove_path(path)

    subprocess.run(["chown", "-R", "user:user", "/home/user"], check=True)
    os.chmod("/home/user", 0o755)
    os.chmod("/home/user/.ssh", 0o700)
    for path, mode in [
        ("/home/user/.ssh/id_ed25519", 0o600),
        ("/home/user/.ssh/id_ed25519.pub", 0o644),
        ("/home/user/.ssh/authorized_keys", 0o600),
        ("/home/user/.ssh/config", 0o600),
        ("/home/user/.ssh/known_hosts", 0o644),
    ]:
        if os.path.exists(path):
            os.chmod(path, mode)

    assert not port_open(9999), "Port 9999 was already listening before the script ran."

    os.makedirs("/run/sshd", exist_ok=True)
    if not port_open(22):
        started = subprocess.run(["/usr/sbin/sshd"], capture_output=True, text=True)
        assert started.returncode == 0, f"Could not start sshd: {started.stderr}"
        for _ in range(40):
            if port_open(22):
                break
            time.sleep(0.05)
        assert port_open(22), "sshd did not begin listening on port 22."

    marker = "TUNNEL_" + uuid.uuid4().hex
    server_code = r'''
import socket, sys
marker = sys.argv[1].encode()
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 8888))
s.listen(20)
while True:
    c, _ = s.accept()
    try:
        c.sendall(marker)
    finally:
        c.close()
'''
    server = subprocess.Popen(
        ["python3", "-u", "-c", server_code, marker],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        for _ in range(40):
            if port_open(8888):
                break
            if server.poll() is not None:
                raise AssertionError(f"Port 8888 test server failed: {server.stderr.read()}")
            time.sleep(0.05)
        assert port_open(8888), "Could not start the tunnel destination on port 8888."

        env = os.environ.copy()
        env.update({"HOME": "/home/user", "USER": "user", "LOGNAME": "user"})
        process = subprocess.Popen(
            ["bash", script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            preexec_fn=user_preexec,
        )

        deadline = time.monotonic() + 35
        tunnel_first = None
        tunnel_last = None
        while process.poll() is None and time.monotonic() < deadline:
            try:
                with socket.create_connection(("127.0.0.1", 9999), timeout=0.2) as conn:
                    conn.settimeout(0.5)
                    data = conn.recv(256).decode(errors="replace")
                    if data == marker:
                        now = time.monotonic()
                        tunnel_first = tunnel_first or now
                        tunnel_last = now
            except OSError:
                pass
            time.sleep(0.05)

        if process.poll() is None:
            process.kill()
            stdout, stderr = process.communicate()
            pytest.fail(f"Script timed out.\nSTDOUT:\n{stdout}\nSTDERR:\n{stderr}")

        stdout, stderr = process.communicate()
        assert process.returncode == 0, (
            f"Script failed with exit code {process.returncode}.\n"
            f"STDOUT:\n{stdout}\nSTDERR:\n{stderr}"
        )
        assert tunnel_first is not None, (
            "The script never established a working SSH forwarding tunnel from port 9999 to port 8888."
        )
        assert tunnel_last - tunnel_first >= 1.4, (
            "The SSH tunnel was not kept active for the required wait period."
        )
    finally:
        server.terminate()
        try:
            server.wait(timeout=2)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait()

    time.sleep(1)


def test_deploy_log_exists_and_correct():
    log_path = "/home/user/deploy.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."
    with open(log_path, "r") as f:
        content = f.read()
    assert "DEPLOYMENT_SUCCESSFUL" in content, (
        f"Log file {log_path} does not contain 'DEPLOYMENT_SUCCESSFUL'."
    )
    assert content == "DEPLOYMENT_SUCCESSFUL\n", "Deployment log does not contain the exact required line."


def test_deployed_file_exists_and_correct():
    app_path = "/home/user/iot-active/sensor_app.sh"
    assert os.path.isfile(app_path), f"Deployed file {app_path} is missing."
    with open(app_path, "r") as f:
        content = f.read()
    assert "Reading sensor data" in content, f"Deployed file {app_path} content is incorrect."


def test_git_repositories_commit_remote_and_hook():
    bare = "/home/user/iot-device.git"
    workspace = "/home/user/workspace"
    hook = os.path.join(bare, "hooks", "post-receive")

    assert os.path.isdir(bare), "Bare deployment repository is missing."
    result = run_user(["git", "-C", bare, "rev-parse", "--is-bare-repository"], capture_output=True, text=True)
    assert result.returncode == 0 and result.stdout.strip() == "true", "iot-device.git is not a bare Git repository."
    assert os.path.isfile(hook), "post-receive hook is missing."
    assert os.access(hook, os.X_OK), "post-receive hook is not executable."

    result = run_user(["git", "-C", workspace, "rev-parse", "--is-inside-work-tree"], capture_output=True, text=True)
    assert result.returncode == 0 and result.stdout.strip() == "true", "workspace is not a Git repository."
    branch = run_user(["git", "-C", workspace, "symbolic-ref", "--short", "HEAD"], capture_output=True, text=True, check=True)
    assert branch.stdout.strip() == "master", "The workspace commit is not on the master branch."

    committed = run_user(["git", "-C", workspace, "show", "HEAD:sensor_app.sh"], capture_output=True, text=True, check=True)
    assert committed.stdout.strip() == 'echo "Reading sensor data"', "sensor_app.sh was not committed with the required content."

    remote = run_user(["git", "-C", workspace, "remote", "get-url", "edge"], capture_output=True, text=True, check=True)
    remote_path = remote.stdout.strip()
    if remote_path.startswith("file://"):
        remote_path = remote_path[7:]
    assert os.path.realpath(remote_path) == os.path.realpath(bare), "Remote 'edge' does not point to the bare repository."

    workspace_head = run_user(["git", "-C", workspace, "rev-parse", "master"], capture_output=True, text=True, check=True).stdout.strip()
    bare_head = run_user(["git", "-C", bare, "rev-parse", "refs/heads/master"], capture_output=True, text=True, check=True).stdout.strip()
    assert workspace_head == bare_head, "The workspace master branch was not pushed to edge/master."


def test_post_receive_hook_deploys_new_unpredictable_commit():
    workspace = "/home/user/workspace"
    token = uuid.uuid4().hex
    filename = f"probe_{token}.txt"
    content = f"verification-{uuid.uuid4().hex}\n"

    writer = "import pathlib,sys; pathlib.Path(sys.argv[1]).write_text(sys.argv[2])"
    run_user(["python3", "-c", writer, os.path.join(workspace, filename), content], check=True)
    run_user(["git", "-C", workspace, "add", filename], check=True)
    run_user(["git", "-C", workspace, "commit", "-m", f"Verifier probe {token}"], capture_output=True, text=True, check=True)

    remove_path("/home/user/iot-active")
    if os.path.lexists("/home/user/deploy.log"):
        remove_path("/home/user/deploy.log")

    pushed = run_user(
        ["git", "-C", workspace, "push", "edge", "master"],
        capture_output=True,
        text=True,
    )
    assert pushed.returncode == 0, f"Push to edge failed.\nSTDOUT:\n{pushed.stdout}\nSTDERR:\n{pushed.stderr}"

    deployed_probe = os.path.join("/home/user/iot-active", filename)
    assert os.path.isfile(deployed_probe), "The post-receive hook did not deploy a newly pushed file."
    with open(deployed_probe, "r") as f:
        assert f.read() == content, "The newly pushed file was not deployed with its committed content."
    assert os.path.isfile("/home/user/iot-active/sensor_app.sh"), "The hook did not extract the complete pushed tree."
    with open("/home/user/deploy.log", "r") as f:
        assert f.read() == "DEPLOYMENT_SUCCESSFUL\n", "The hook did not write the exact required deployment log."


def test_ssh_tunnel_closed():
    try:
        result = subprocess.run(["ss", "-tln"], capture_output=True, text=True, check=True)
        assert ":9999 " not in result.stdout, "SSH tunnel was not closed; port 9999 is still listening."
    except FileNotFoundError:
        result = subprocess.run(["netstat", "-tln"], capture_output=True, text=True)
        assert ":9999 " not in result.stdout, "SSH tunnel was not closed; port 9999 is still listening."

    assert not port_open(9999), "SSH tunnel was not closed; port 9999 still accepts connections."
    processes = subprocess.run(["ps", "-u", "user", "-o", "args="], capture_output=True, text=True, check=True)
    lingering = [line for line in processes.stdout.splitlines() if "9999" in line and "8888" in line and "ssh" in line]
    assert not lingering, f"SSH tunnel process was not terminated: {lingering}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
