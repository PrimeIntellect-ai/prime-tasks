#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import signal
import socket
import subprocess
import tempfile
import time
import pytest

EXPECTED_TOKEN = "8f9b2a7c-4e1d-48a5-9032-abcdef123456"
BARE_REPO = "/home/user/deploy.git"
WORKSPACE = "/home/user/workspace"
DEPLOYED_DIR = "/home/user/deployed_service"
BINARY_PATH = os.path.join(DEPLOYED_DIR, "server_bin")
SOURCE_PATH = os.path.join(WORKSPACE, "server.c")


def git(*args, cwd=None, timeout=20):
    return subprocess.run(
        ["git", "-c", "safe.directory=*", *args],
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=True,
    ).stdout.strip()


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return result


def stop_port(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.1)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def read_service():
    with socket.create_connection(("127.0.0.1", 9090), timeout=5.0) as s:
        s.settimeout(5.0)
        chunks = []
        while True:
            chunk = s.recv(1024)
            if not chunk:
                break
            chunks.append(chunk)
        return b"".join(chunks).decode("utf-8")


def wait_for_service():
    deadline = time.time() + 10
    last_error = None
    while time.time() < deadline:
        try:
            return read_service()
        except (ConnectionRefusedError, socket.timeout, OSError) as exc:
            last_error = exc
            time.sleep(0.2)
    pytest.fail(f"Service did not start on 127.0.0.1:9090: {last_error}")


@pytest.fixture(scope="session", autouse=True)
def verify_and_trigger_git_deployment():
    # Derive the token from the supplied backup image rather than trusting only
    # a value embedded in the test.
    ocr = subprocess.run(
        ["tesseract", "/app/backup_config.png", "stdout"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        timeout=20,
    ).stdout
    match = re.search(r"AUTH_TOKEN\s*:\s*([0-9a-fA-F-]{36})", ocr)
    assert match, "AUTH_TOKEN UUID was not found by OCR in backup_config.png"
    assert match.group(1) == EXPECTED_TOKEN

    assert os.path.isdir(BARE_REPO), f"Bare repository {BARE_REPO} does not exist"
    assert git("-C", BARE_REPO, "rev-parse", "--is-bare-repository") == "true"
    assert os.path.isdir(os.path.join(BARE_REPO, "objects"))
    assert os.path.isdir(os.path.join(BARE_REPO, "refs"))

    assert os.path.isdir(os.path.join(WORKSPACE, ".git")), f"{WORKSPACE} is not a Git clone"
    branch = git("-C", WORKSPACE, "symbolic-ref", "--short", "HEAD")
    workspace_head = git("-C", WORKSPACE, "rev-parse", "HEAD")
    assert git("-C", WORKSPACE, "ls-files", "--error-unmatch", "server.c") == "server.c"
    committed_source = git("-C", WORKSPACE, "show", "HEAD:server.c").encode()
    with open(SOURCE_PATH, "rb") as f:
        assert f.read() == committed_source, "workspace/server.c has uncommitted content"

    remote_urls = []
    for remote in git("-C", WORKSPACE, "remote").splitlines():
        remote_urls.extend(git("-C", WORKSPACE, "remote", "get-url", "--all", remote).splitlines())
    normalized = []
    for url in remote_urls:
        if url.startswith("file://"):
            url = url[7:]
        if os.path.isabs(url):
            normalized.append(os.path.realpath(url))
    assert os.path.realpath(BARE_REPO) in normalized, "workspace has no remote pointing to deploy.git"

    bare_ref = f"refs/heads/{branch}"
    assert git("-C", BARE_REPO, "rev-parse", "--verify", bare_ref) == workspace_head, \
        "The workspace commit was not pushed to deploy.git"

    hook_path = os.path.join(BARE_REPO, "hooks", "post-receive")
    assert os.path.isfile(hook_path)
    assert os.access(hook_path, os.X_OK)

    # Remove the previous deployment and listener, then make a real push. The
    # only opportunity to recreate and start the deployment is post-receive.
    stop_port(9090)
    shutil.rmtree(DEPLOYED_DIR, ignore_errors=True)

    with tempfile.TemporaryDirectory(prefix="verify-push-") as temp:
        clone = os.path.join(temp, "clone")
        git("clone", "--no-checkout", BARE_REPO, clone, timeout=30)
        git("-C", clone, "checkout", "-B", branch, f"origin/{branch}")
        git("-C", clone, "config", "user.name", "Verifier")
        git("-C", clone, "config", "user.email", "verifier@localhost")
        git("-C", clone, "commit", "--allow-empty", "-m", "Verify post-receive deployment")
        pushed_head = git("-C", clone, "rev-parse", "HEAD")
        subprocess.run(
            ["git", "-c", "safe.directory=*", "-C", clone, "push", "origin", f"HEAD:{bare_ref}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
            check=True,
        )

    assert git("-C", BARE_REPO, "rev-parse", "--verify", bare_ref) == pushed_head
    response = wait_for_service()
    assert response.strip() == EXPECTED_TOKEN, \
        f"Expected token '{EXPECTED_TOKEN}', but received '{response.strip()}'"

    assert os.path.isdir(DEPLOYED_DIR), "post-receive did not recreate the deployment directory"
    assert os.path.isfile(os.path.join(DEPLOYED_DIR, "server.c"))
    deployed_expected = subprocess.run(
        ["git", "-c", "safe.directory=*", "-C", BARE_REPO, "show", f"{pushed_head}:server.c"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    ).stdout
    with open(os.path.join(DEPLOYED_DIR, "server.c"), "rb") as f:
        assert f.read() == deployed_expected, "Deployed server.c is not the source from the pushed commit"

    assert os.path.isfile(BINARY_PATH)
    assert os.access(BINARY_PATH, os.X_OK)
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "server_bin is not a compiled executable"

    live_pids = listener_pids(9090)
    assert live_pids, "No process is listening on TCP port 9090"
    assert any(
        os.path.exists(f"/proc/{pid}/exe") and os.path.samefile(f"/proc/{pid}/exe", BINARY_PATH)
        for pid in live_pids
    ), "The process listening on port 9090 is not deployed_service/server_bin"


def test_git_hook_exists_and_executable():
    """Test that the post-receive hook exists and is executable."""
    hook_path = "/home/user/deploy.git/hooks/post-receive"
    assert os.path.exists(hook_path), f"The post-receive hook does not exist at {hook_path}"
    assert os.path.isfile(hook_path), f"The path {hook_path} is not a file"
    assert os.access(hook_path, os.X_OK), f"The post-receive hook at {hook_path} is not executable"


def test_tcp_server_response():
    """Test that the TCP server is running on port 9090 and returns the correct token."""
    host = '127.0.0.1'
    port = 9090
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(5.0)
            s.connect((host, port))
            data = s.recv(1024).decode('utf-8')
            assert data.strip() == EXPECTED_TOKEN, f"Expected token '{EXPECTED_TOKEN}', but received '{data.strip()}'"
    except ConnectionRefusedError:
        pytest.fail(f"Could not connect to the server at {host}:{port}. Is it running?")
    except socket.timeout:
        pytest.fail(f"Connection to {host}:{port} timed out.")
    except Exception as e:
        pytest.fail(f"An error occurred while connecting to the server: {e}")


def test_deployed_files_exist():
    """Test that the deployed service directory and compiled binary exist."""
    deployed_dir = "/home/user/deployed_service"
    binary_path = os.path.join(deployed_dir, "server_bin")
    assert os.path.exists(deployed_dir), f"Deployed service directory {deployed_dir} does not exist"
    assert os.path.exists(binary_path), f"Compiled binary {binary_path} does not exist"
    assert os.access(binary_path, os.X_OK), f"Compiled binary {binary_path} is not executable"


def test_workspace_files_exist():
    """Test that the workspace directory and source file exist."""
    workspace_dir = "/home/user/workspace"
    source_path = os.path.join(workspace_dir, "server.c")
    assert os.path.exists(workspace_dir), f"Workspace directory {workspace_dir} does not exist"
    assert os.path.exists(source_path), f"Source file {source_path} does not exist"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
