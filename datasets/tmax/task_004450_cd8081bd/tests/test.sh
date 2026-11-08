#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import subprocess
import threading
import time


def test_deployment_restore():
    """Verify the backup was extracted and the symlink was created properly."""
    deployments_dir = "/home/user/deployments"
    app_v1 = os.path.join(deployments_dir, "app-v1")
    app_v2 = os.path.join(deployments_dir, "app-v2")
    live_link = os.path.join(deployments_dir, "live")

    assert os.path.isdir(app_v1), f"Expected extracted directory {app_v1} not found."
    assert os.path.isdir(app_v2), f"Expected extracted directory {app_v2} not found."

    assert os.path.islink(live_link), f"Expected {live_link} to be a symbolic link."
    target = os.readlink(live_link)
    if not os.path.isabs(target):
        target = os.path.normpath(os.path.join(deployments_dir, target))
    assert target == app_v2, f"Expected {live_link} to point to {app_v2}, but points to {target}"


def test_storage_monitoring():
    """Verify that large files (>100KB) are logged correctly."""
    log_file = "/home/user/large_files.log"
    assert os.path.isfile(log_file), f"Expected log file {log_file} not found."

    deployments_dir = "/home/user/deployments"
    expected_large_files = set()
    if os.path.isdir(deployments_dir):
        for root, dirs, files in os.walk(deployments_dir):
            for file in files:
                filepath = os.path.join(root, file)
                if not os.path.islink(filepath) and os.path.getsize(filepath) > 100 * 1024:
                    expected_large_files.add(filepath)

    with open(log_file, "r") as f:
        actual_lines = {line.strip() for line in f if line.strip()}

    assert actual_lines == expected_large_files, (
        f"Expected {log_file} to contain exactly {expected_large_files}, but got {actual_lines}"
    )


def test_user_access_administration():
    """Verify the auth file contains a valid APR1 hash for the required password."""
    auth_file = "/home/user/proxy_users.txt"
    assert os.path.isfile(auth_file), f"Expected basic auth file {auth_file} not found."

    with open(auth_file, "r") as f:
        content = f.read().strip()

    assert "backup_admin:" in content, f"Expected user 'backup_admin' in {auth_file}."
    match = re.search(
        r"^backup_admin:\$apr1\$[a-zA-Z0-9./]+\$[a-zA-Z0-9./]+",
        content,
        re.MULTILINE,
    )
    assert match is not None, (
        f"Expected 'backup_admin' to have an Apache MD5 ($apr1$) hashed password in {auth_file}."
    )

    verified = subprocess.run(
        ["htpasswd", "-vb", auth_file, "backup_admin", "staging_pass_2024"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=5,
    )
    assert verified.returncode == 0, (
        "The backup_admin hash does not verify against password staging_pass_2024. "
        f"htpasswd output: {verified.stdout}"
    )


def _process_tree_uses_forwarder(root_pid):
    processes = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        try:
            with open(f"/proc/{pid}/status", "r") as f:
                status = f.read()
            parent_match = re.search(r"^PPid:\s+(\d+)$", status, re.MULTILINE)
            with open(f"/proc/{pid}/comm", "r") as f:
                command = f.read().strip()
            if parent_match:
                processes[pid] = (int(parent_match.group(1)), command)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass

    descendants = {root_pid}
    changed = True
    while changed:
        changed = False
        for pid, (parent, command) in processes.items():
            if parent in descendants and pid not in descendants:
                descendants.add(pid)
                changed = True

    accepted = {"socat", "nc", "nc.openbsd", "ncat"}
    return any(processes.get(pid, (None, ""))[1] in accepted for pid in descendants)


def test_proxy_setup():
    """Execute the proxy and verify that it forwards repeated TCP connections."""
    script_file = "/home/user/start_proxy.sh"
    assert os.path.isfile(script_file), f"Expected script file {script_file} not found."
    assert os.access(script_file, os.X_OK), f"Expected {script_file} to be executable."

    with open(script_file, "r") as f:
        content = f.read()

    assert "8080" in content, f"Expected reference to port 8080 in {script_file}."
    assert "9090" in content, f"Expected reference to port 9090 in {script_file}."

    non_comment_code = "\n".join(
        line for line in content.splitlines() if not line.lstrip().startswith("#")
    )
    assert re.search(r"(?<![\w-])(socat|nc|ncat)(?![\w-])", non_comment_code), (
        f"Expected {script_file} to invoke socat, nc, or ncat."
    )

    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.settimeout(0.25)
    try:
        assert probe.connect_ex(("127.0.0.1", 8080)) != 0, (
            "TCP port 8080 was already occupied before the submitted script was started."
        )
    finally:
        probe.close()

    backend = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    backend.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    backend.bind(("127.0.0.1", 9090))
    backend.listen(10)
    backend.settimeout(0.2)
    stop_backend = threading.Event()

    def backend_loop():
        while not stop_backend.is_set():
            try:
                conn, _ = backend.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            with conn:
                conn.settimeout(2)
                try:
                    while True:
                        data = conn.recv(65536)
                        if not data:
                            break
                        conn.sendall(data)
                except (socket.timeout, ConnectionError, OSError):
                    pass

    thread = threading.Thread(target=backend_loop, daemon=True)
    thread.start()

    proc = None
    try:
        proc = subprocess.Popen(
            [script_file],
            cwd="/home/user",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            preexec_fn=os.setsid,
        )

        deadline = time.time() + 5
        listening = False
        while time.time() < deadline:
            if proc.poll() is not None:
                break
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(0.2)
            try:
                if sock.connect_ex(("127.0.0.1", 8080)) == 0:
                    listening = True
                    break
            finally:
                sock.close()
            time.sleep(0.1)

        stderr = ""
        if not listening and proc.poll() is not None and proc.stderr:
            stderr = proc.stderr.read()
        assert listening, f"The submitted script did not listen on TCP port 8080. {stderr}"
        assert proc.poll() is None, "The submitted proxy exited instead of running continuously."

        tool_deadline = time.time() + 2
        used_forwarder = False
        while time.time() < tool_deadline:
            if _process_tree_uses_forwarder(proc.pid):
                used_forwarder = True
                break
            time.sleep(0.05)
        assert used_forwarder, "No running socat, nc, or ncat process was found in the proxy process tree."

        def exchange(payload):
            connect_deadline = time.time() + 3
            while True:
                try:
                    client = socket.create_connection(("127.0.0.1", 8080), timeout=0.5)
                    break
                except OSError:
                    if time.time() >= connect_deadline:
                        raise AssertionError("Proxy stopped accepting connections on TCP port 8080.")
                    time.sleep(0.1)
            with client:
                client.settimeout(3)
                client.sendall(payload)
                received = b""
                while len(received) < len(payload):
                    chunk = client.recv(len(payload) - len(received))
                    if not chunk:
                        break
                    received += chunk
            assert received == payload, (
                f"Proxy did not forward traffic to localhost:9090; sent {payload!r}, got {received!r}."
            )

        exchange(b"first-forwarding-check\n")
        exchange(b"second-forwarding-check\n")
        assert proc.poll() is None, "The proxy did not remain running for multiple connections."
    finally:
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
                proc.wait(timeout=2)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        stop_backend.set()
        backend.close()
        thread.join(timeout=1)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
