#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import socket
import stat
import subprocess
import threading
import time

HOOK_PATH = "/home/user/repo.git/hooks/post-receive"
DAEMON_PATH = "/home/user/app/deploy_daemon.sh"
SOCKET_PATH = "/home/user/upstream.sock"
LOG_PATH = "/home/user/app/deploy.log"


def test_post_receive_executable():
    assert os.path.isfile(HOOK_PATH), f"The post-receive hook {HOOK_PATH} does not exist."

    st = os.stat(HOOK_PATH)
    is_executable = bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
    assert is_executable, f"The post-receive hook {HOOK_PATH} is not executable. You need to fix its permissions."


def test_deploy_log_success():
    assert os.path.isfile(LOG_PATH), f"The deploy log {LOG_PATH} does not exist. Did the pipeline run successfully?"

    with open(LOG_PATH, 'r') as f:
        content = f.read()

    assert "DEPLOY_SUCCESS" in content, f"The deploy log does not contain 'DEPLOY_SUCCESS'. Found instead: {content.strip()}"


def test_post_receive_socket_path_fixed():
    assert os.path.isfile(HOOK_PATH), f"The post-receive hook {HOOK_PATH} does not exist."

    with open(HOOK_PATH, 'r') as f:
        content = f.read()

    assert SOCKET_PATH in content, "The post-receive hook does not contain the correct upstream socket path."
    assert "/home/user/app/upstream.sock" not in content, "The post-receive hook still contains the misconfigured socket path."


def _processes_running_script():
    matches = []
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            with open(f'/proc/{name}/cmdline', 'rb') as f:
                argv = [part.decode(errors='replace') for part in f.read().split(b'\0') if part]
            if DAEMON_PATH in argv:
                matches.append(int(name))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return matches


def _descendants(roots):
    parent_map = {}
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            with open(f'/proc/{name}/status', 'r') as f:
                ppid = None
                for line in f:
                    if line.startswith('PPid:'):
                        ppid = int(line.split()[1])
                        break
            if ppid is not None:
                parent_map.setdefault(ppid, []).append(int(name))
        except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
            pass

    found = set(roots)
    pending = list(roots)
    while pending:
        parent = pending.pop()
        for child in parent_map.get(parent, []):
            if child not in found:
                found.add(child)
                pending.append(child)
    return found


def _stop_daemon_tree(roots):
    pids = _descendants(roots)
    for pid in sorted(pids, reverse=True):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.2)
    for pid in sorted(pids, reverse=True):
        try:
            os.kill(pid, 0)
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass


def _restart_daemon():
    subprocess.Popen(
        [DAEMON_PATH],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            if stat.S_ISSOCK(os.stat(SOCKET_PATH).st_mode):
                return
        except FileNotFoundError:
            pass
        time.sleep(0.05)


def test_pipeline_really_uses_running_daemon_and_unix_socket():
    daemon_pids = _processes_running_script()
    assert daemon_pids, f"The deployment daemon {DAEMON_PATH} is not running."

    try:
        socket_stat = os.stat(SOCKET_PATH)
    except FileNotFoundError:
        raise AssertionError(f"The daemon socket {SOCKET_PATH} does not exist.")
    assert stat.S_ISSOCK(socket_stat.st_mode), f"{SOCKET_PATH} is not a Unix domain socket."

    # Exercise the already-running daemon independently and require a fresh result.
    try:
        os.unlink(LOG_PATH)
    except FileNotFoundError:
        pass
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(3)
    client.connect(SOCKET_PATH)
    client.sendall(b'DEPLOY\n')
    client.close()

    deadline = time.time() + 3
    while time.time() < deadline and not os.path.isfile(LOG_PATH):
        time.sleep(0.05)
    assert os.path.isfile(LOG_PATH), "The running daemon did not create the deployment log after receiving DEPLOY."
    with open(LOG_PATH, 'r') as f:
        assert "DEPLOY_SUCCESS" in f.read(), "The running daemon did not record DEPLOY_SUCCESS."

    # Replace only the socket pathname with a controlled listener. This proves the
    # hook itself sends DEPLOY through the required Unix socket rather than merely
    # writing the success log directly.
    server = None
    listener_thread = None
    received = []
    listener_errors = []
    displaced_socket = False
    try:
        os.unlink(SOCKET_PATH)
        displaced_socket = True
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(SOCKET_PATH)
        server.listen(1)
        server.settimeout(5)

        def receive_from_hook():
            try:
                conn, _ = server.accept()
                conn.settimeout(3)
                data = b''
                while True:
                    chunk = conn.recv(1024)
                    if not chunk:
                        break
                    data += chunk
                    if b'DEPLOY' in data:
                        break
                received.append(data)
                conn.close()
            except Exception as exc:
                listener_errors.append(exc)

        listener_thread = threading.Thread(target=receive_from_hook)
        listener_thread.start()
        result = subprocess.run(
            [HOOK_PATH],
            input=b"refs/heads/main\n",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=8,
        )
        listener_thread.join(timeout=6)

        assert result.returncode == 0, (
            f"The post-receive hook failed with status {result.returncode}: "
            f"{result.stderr.decode(errors='replace')}"
        )
        assert not listener_thread.is_alive(), "The hook never connected to the required Unix socket."
        assert not listener_errors, f"Failed while receiving from the hook: {listener_errors[0]}"
        assert received and b'DEPLOY' in received[0], (
            f"The hook connected but did not send DEPLOY. Received: {received[0] if received else b''!r}"
        )
    finally:
        if server is not None:
            server.close()
        if displaced_socket:
            try:
                os.unlink(SOCKET_PATH)
            except FileNotFoundError:
                pass
            _stop_daemon_tree(daemon_pids)
            _restart_daemon()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
