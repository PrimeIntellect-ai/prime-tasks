#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import socket
import subprocess
import threading
import time
import shutil
import uuid

import pytest

notifications = []
notifications_lock = threading.Lock()
server_stop = threading.Event()


def notification_server():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 2525))
    srv.listen(20)
    srv.settimeout(0.2)
    while not server_stop.is_set():
        try:
            conn, _ = srv.accept()
        except socket.timeout:
            continue
        with conn:
            conn.settimeout(1)
            data = b""
            while True:
                try:
                    chunk = conn.recv(4096)
                except socket.timeout:
                    break
                if not chunk:
                    break
                data += chunk
            with notifications_lock:
                notifications.append(data)
    srv.close()


def listener_inodes(port):
    wanted = f"{port:04X}"
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def kill_port_listeners(port):
    inodes = listener_inodes(port)
    if not inodes:
        return
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    try:
                        os.kill(int(pid), signal.SIGTERM)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except (FileNotFoundError, PermissionError):
            pass
    time.sleep(0.3)


def wait_for_port(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.2)
            if sock.connect_ex(("127.0.0.1", port)) == 0:
                return
        time.sleep(0.1)
    pytest.fail(f"Port {port} did not become available")


# The supplied image omitted the claimed notification service. Start a real test
# endpoint here, after first removing any agent-created substitute on that port.
kill_port_listeners(2525)
server_thread = threading.Thread(target=notification_server, daemon=True)
server_thread.start()
wait_for_port(2525)


def test_auto_approve_script():
    exp_path = "/home/user/auto-approve.exp"
    assert os.path.isfile(exp_path), f"Expect script {exp_path} is missing."
    assert os.access(exp_path, os.X_OK), f"Expect script {exp_path} is not executable."

    result = subprocess.run([exp_path], capture_output=True, timeout=10)
    output = result.stdout.decode(errors="replace") + result.stderr.decode(errors="replace")
    assert result.returncode == 0, f"Expect script failed to run successfully. Output: {output}"
    assert "Manifests approved." in output, "The Expect script did not successfully complete the interactive approval tool."


def test_port_forwarding():
    script = "/home/user/port-forward.sh"
    assert os.path.isfile(script), f"Port-forward script {script} is missing."
    assert os.access(script, os.X_OK), f"Port-forward script {script} is not executable."

    # Exercise the submitted artifact itself, rather than trusting an arbitrary
    # listener the agent may have placed on 10025.
    kill_port_listeners(10025)
    subprocess.Popen([script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    wait_for_port(10025)

    processes = subprocess.run(["pgrep", "-a", "socat"], capture_output=True, text=True)
    assert processes.returncode == 0, "The port-forward script did not start socat."
    assert "10025" in processes.stdout and "2525" in processes.stdout, \
        f"No socat process forwards 10025 to 2525: {processes.stdout}"

    token = ("forward-" + uuid.uuid4().hex).encode()
    with notifications_lock:
        notifications.clear()
    with socket.create_connection(("127.0.0.1", 10025), timeout=2) as sock:
        sock.sendall(token)
        sock.shutdown(socket.SHUT_WR)

    deadline = time.time() + 3
    while time.time() < deadline:
        with notifications_lock:
            if any(token in message for message in notifications):
                break
        time.sleep(0.05)
    else:
        pytest.fail("Traffic sent to 10025 did not reach the notification service on 2525.")

    # Preserve the original active-listener assertion.
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(2)
    result = sock.connect_ex(("127.0.0.1", 10025))
    sock.close()
    assert result == 0, "Port 10025 is not open or forwarded. The socat port forwarding might not be running."


def test_git_hook_exists():
    hook_path = "/home/user/manifests.git/hooks/post-receive"
    assert os.path.isfile(hook_path), f"Git hook {hook_path} is missing."
    assert os.access(hook_path, os.X_OK), f"Git hook {hook_path} is not executable."


def test_end_to_end_git_push():
    temp_repo = "/tmp/test-repo"
    if os.path.exists(temp_repo):
        shutil.rmtree(temp_repo)
    os.makedirs(temp_repo)

    token = "manifest-" + uuid.uuid4().hex
    trace = "/tmp/hook-trace-" + uuid.uuid4().hex

    subprocess.run(["git", "init", "-b", "master"], cwd=temp_repo, check=True, capture_output=True)
    subprocess.run(["git", "remote", "add", "origin", "/home/user/manifests.git"], cwd=temp_repo, check=True, capture_output=True)
    with open(os.path.join(temp_repo, "deployment.yaml"), "w") as f:
        f.write("apiVersion: v1\nmetadata:\n  name: " + token + "\n")
    subprocess.run(["git", "add", "deployment.yaml"], cwd=temp_repo, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=temp_repo, check=True)
    subprocess.run(["git", "config", "user.name", "Test User"], cwd=temp_repo, check=True)
    subprocess.run(["git", "commit", "-m", "Test deployment " + token], cwd=temp_repo, check=True, capture_output=True)

    approve = "/home/user/bin/approve-manifests"
    validator = "/home/user/bin/validator-daemon.sh"
    applier = "/home/user/bin/applier.sh"
    backups = {p: p + ".verifier-original" for p in (approve, validator, applier)}

    kill_port_listeners(8080)
    for path, backup in backups.items():
        if os.path.exists(backup):
            os.remove(backup)
        os.replace(path, backup)

    approve_wrapper = f'''#!/bin/bash
read -p "Enter operator password: " pass
[ "$pass" = "k8s-ops-secret" ] || exit 41
read -p "Confirm deployment (yes/no): " answer
[ "$answer" = "yes" ] || exit 42
grep -q {token!r} /home/user/deploy-stage/deployment.yaml || exit 43
echo approval >> {trace!r}
echo "Manifests approved."
'''
    validator_wrapper = f'''#!/bin/bash
echo validator-start >> {trace!r}
exec {backups[validator]!r}
'''
    applier_wrapper = f'''#!/bin/bash
[ "$1" = "/home/user/deploy-stage/" ] || exit 51
nc -z 127.0.0.1 8080 || exit 52
grep -q {token!r} /home/user/deploy-stage/deployment.yaml || exit 53
echo applier >> {trace!r}
exec {backups[applier]!r} "$@"
'''

    for path, content in ((approve, approve_wrapper), (validator, validator_wrapper), (applier, applier_wrapper)):
        with open(path, "w") as f:
            f.write(content)
        os.chmod(path, 0o755)

    log_path = "/home/user/deploy-stage/applied.log"
    if os.path.exists(log_path):
        os.remove(log_path)
    with notifications_lock:
        notifications.clear()

    try:
        push_result = subprocess.run(
            ["git", "push", "--force", "origin", "HEAD:master"],
            cwd=temp_repo, capture_output=True, timeout=30
        )
        assert push_result.returncode == 0, \
            f"Git push failed. Output: {push_result.stderr.decode(errors='replace')}"

        # Preserve the original settling delay and assertions.
        time.sleep(5)
        assert os.path.isfile(log_path), f"Log file {log_path} was not created. The hook may have failed or not run."
        with open(log_path) as f:
            content = f.read()
        expected_msg = "Successfully applied manifests from /home/user/deploy-stage/"
        assert expected_msg in content, f"Expected success message not found in {log_path}. Content: {content}"

        with open("/home/user/deploy-stage/deployment.yaml") as f:
            staged = f.read()
        assert token in staged, "The hook did not check out the newly pushed master revision into deploy-stage."

        assert os.path.isfile(trace), "The hook did not execute the instrumented pipeline programs."
        with open(trace) as f:
            events = [line.strip() for line in f if line.strip()]
        assert events == ["approval", "validator-start", "applier"], \
            f"Pipeline actions were missing or out of order: {events}"

        deadline = time.time() + 3
        while time.time() < deadline:
            with notifications_lock:
                if any(b"Mock email sent" in message for message in notifications):
                    break
            time.sleep(0.05)
        else:
            pytest.fail("The applier's notification did not traverse 10025 to the service on 2525.")
    finally:
        kill_port_listeners(8080)
        for path, backup in backups.items():
            if os.path.exists(path):
                os.remove(path)
            if os.path.exists(backup):
                os.replace(backup, path)
        if os.path.exists(trace):
            os.remove(trace)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
