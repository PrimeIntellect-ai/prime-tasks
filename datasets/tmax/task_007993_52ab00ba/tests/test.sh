#!/bin/bash
set -u
mkdir -p /logs/verifier

cleanup() {
    if [ -f /tmp/capacity_service.pid ]; then
        kill "$(cat /tmp/capacity_service.pid)" 2>/dev/null || true
    fi
    pkill -f 'ssh.*9999:localhost:8888' 2>/dev/null || true
    /usr/bin/apptainer instance stop metric_sandbox >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Replace the fixed mock endpoint during verification with a one-shot endpoint
# whose nonce is generated only when the test starts.
pkill -x socat 2>/dev/null || true
rm -f /tmp/capacity_service_trace.json /tmp/capacity_service_ready
cat > /tmp/capacity_test_service.py <<'PY'
import json
import os
import secrets
import socket
import time

TRACE = "/tmp/capacity_service_trace.json"

def socket_owners(peer_port):
    wanted = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10 or fields[3] != "01":
                continue
            try:
                local_port = int(fields[1].rsplit(":", 1)[1], 16)
                remote_port = int(fields[2].rsplit(":", 1)[1], 16)
            except ValueError:
                continue
            # This is the client side of the connection accepted on 8888.
            if local_port == peer_port and remote_port == 8888:
                wanted.append(fields[9])

    owners = []
    wanted = set(wanted)
    if not wanted:
        return owners
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            links = [os.readlink(os.path.join(fd_dir, fd)) for fd in os.listdir(fd_dir)]
        except (OSError, PermissionError):
            continue
        if not any(link.startswith("socket:[") and link[8:-1] in wanted for link in links):
            continue
        try:
            cmd = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
        except OSError:
            cmd = ""
        owners.append({"pid": int(pid), "cmdline": cmd})
    return owners

def recvline(conn):
    data = bytearray()
    while len(data) < 1024:
        part = conn.recv(1)
        if not part or part in (b"\n", b"\r"):
            break
        data.extend(part)
    return data.decode(errors="replace")

payload_obj = {
    "status": "ok",
    "cpu_usage": 74.5,
    "mem_usage": 82.1,
    "nodes_active": 42,
    "verification_nonce": secrets.token_hex(20),
}
payload = json.dumps(payload_obj, separators=(",", ":"))

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 8888))
srv.listen(1)
open("/tmp/capacity_service_ready", "w").close()
srv.settimeout(150)
trace = {"connected": False}
try:
    conn, peer = srv.accept()
    with conn:
        time.sleep(0.08)
        trace["connected"] = True
        trace["peer"] = list(peer)
        trace["owners"] = socket_owners(peer[1])
        conn.sendall(b"Login: ")
        username = recvline(conn)
        trace["username"] = username
        if username != "planner":
            conn.sendall(b"Invalid user\n")
        else:
            conn.sendall(b"Password: ")
            password = recvline(conn)
            trace["password"] = password
            if password != "metrics_pass_99":
                conn.sendall(b"Invalid password\n")
            else:
                conn.sendall(payload.encode() + b"\n")
                trace["payload"] = payload
finally:
    with open(TRACE, "w") as f:
        json.dump(trace, f)
    srv.close()
PY
python3 /tmp/capacity_test_service.py >/tmp/capacity_service.log 2>&1 &
echo $! > /tmp/capacity_service.pid
for _ in $(seq 1 100); do
    [ -e /tmp/capacity_service_ready ] && break
    sleep 0.05
done

cat <<'PY' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
import threading
import time
from pathlib import Path

REPO = Path("/home/user/capacity_control.git")
CONTENTS = Path("/home/user/repo_contents")
REPORT = Path("/home/user/capacity_report.json")
TRACE = Path("/tmp/capacity_service_trace.json")


def run(args, **kwargs):
    return subprocess.run(args, text=True, capture_output=True, **kwargs)


def test_bare_repo_exists():
    assert REPO.is_dir(), f"Bare repository directory not found at {REPO}"
    config_path = REPO / "config"
    assert config_path.is_file(), f"Git config not found in {REPO}"
    config_content = config_path.read_text()
    assert "bare = true" in config_content.lower(), f"Repository at {REPO} is not configured as bare"
    result = run(["git", "--git-dir", str(REPO), "rev-parse", "--is-bare-repository"])
    assert result.returncode == 0 and result.stdout.strip() == "true"


def test_post_receive_hook_exists_and_executable():
    hook = REPO / "hooks/post-receive"
    assert hook.is_file(), f"post-receive hook not found at {hook}"
    assert os.access(hook, os.X_OK), f"post-receive hook at {hook} is not executable"


def test_repo_contents_prepared():
    trigger = CONTENTS / "trigger_analysis.sh"
    assert trigger.is_file(), f"trigger_analysis.sh not found at {trigger}"

    files = [p for p in CONTENTS.rglob("*") if p.is_file() and ".git" not in p.parts]
    combined = "\n".join(p.read_text(errors="ignore") for p in files)
    trigger_text = trigger.read_text(errors="ignore")

    # Keep structural checks in addition to the behavioral execution below.
    assert "ssh" in trigger_text and "9999" in trigger_text and "8888" in trigger_text
    assert "user@localhost" in trigger_text
    assert "docker://alpine:latest" in trigger_text and "/home/user/alpine.sif" in trigger_text
    assert "metric_sandbox" in trigger_text and "apptainer" in trigger_text.lower()
    assert "instance" in trigger_text.lower() and "stop" in trigger_text.lower()
    assert "expect" in combined.lower(), "No Expect-based interaction was prepared"
    for required in ("Login:", "Password:", "planner", "metrics_pass_99", "9999", "capacity_report.json"):
        assert required in combined, f"Prepared scripts do not contain required interaction element: {required}"


def test_pipeline_execution():
    assert Path("/tmp/capacity_service_ready").exists(), "Dynamic metric service did not start"

    # Ensure only this push can create the tested artifacts.
    REPORT.unlink(missing_ok=True)
    Path("/home/user/alpine.sif").unlink(missing_ok=True)
    shutil.rmtree("/home/user/capacity_workspace", ignore_errors=True)
    shutil.rmtree(CONTENTS / ".git", ignore_errors=True)

    observed = []
    stop_monitor = threading.Event()

    def monitor_processes():
        while not stop_monitor.is_set():
            snapshot = []
            for entry in Path("/proc").iterdir():
                if not entry.name.isdigit():
                    continue
                try:
                    cmd = (entry / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="ignore")
                except OSError:
                    continue
                if any(word in cmd.lower() for word in ("apptainer", "metric_sandbox", "ssh", "expect", " nc ")):
                    snapshot.append(cmd)
            observed.extend(snapshot)
            time.sleep(0.01)

    monitor = threading.Thread(target=monitor_processes, daemon=True)
    monitor.start()
    try:
        for args in (
            ["git", "init", "--initial-branch=master"],
            ["git", "config", "user.email", "test@example.com"],
            ["git", "config", "user.name", "Test User"],
            ["git", "remote", "add", "origin", str(REPO)],
            ["git", "add", "."],
            ["git", "commit", "-m", "Test trigger"],
        ):
            result = run(args, cwd=CONTENTS)
            assert result.returncode == 0, f"Command failed: {args}\n{result.stdout}\n{result.stderr}"

        pushed_commit = run(["git", "rev-parse", "HEAD"], cwd=CONTENTS).stdout.strip()
        push = run(["git", "push", "--force", "origin", "master"], cwd=CONTENTS, timeout=150)
        assert push.returncode == 0, f"Push/hook failed:\nstdout={push.stdout}\nstderr={push.stderr}"

        deadline = time.time() + 30
        while time.time() < deadline and (not REPORT.is_file() or not TRACE.is_file()):
            time.sleep(0.1)
    finally:
        stop_monitor.set()
        monitor.join(timeout=2)

    assert REPORT.is_file(), f"The file {REPORT} was not created after pushing"
    assert TRACE.is_file(), "The interactive service was never completed"

    remote_commit = run(["git", "--git-dir", str(REPO), "rev-parse", "refs/heads/master"])
    assert remote_commit.returncode == 0 and remote_commit.stdout.strip() == pushed_commit
    workspace_trigger = Path("/home/user/capacity_workspace/trigger_analysis.sh")
    assert workspace_trigger.is_file(), "The hook did not extract the pushed commit into capacity_workspace"
    assert workspace_trigger.read_bytes() == (CONTENTS / "trigger_analysis.sh").read_bytes()

    trace = json.loads(TRACE.read_text())
    assert trace.get("connected") is True
    assert trace.get("username") == "planner"
    assert trace.get("password") == "metrics_pass_99"
    assert any("sshd" in item.get("cmdline", "").lower() for item in trace.get("owners", [])), \
        f"The service connection was not made by an SSH-forwarding process: {trace.get('owners')}"

    # Exact equality, including an unpredictable nonce, prevents a script from
    # writing the fixed payload exposed by mock_service.sh.
    content = REPORT.read_text().strip()
    assert content == trace["payload"], f"Report was not the exact payload returned by the service: {content}"
    data = json.loads(content)
    assert "cpu_usage" in data
    assert data["cpu_usage"] == 74.5
    assert data.get("status") == "ok"
    assert data.get("verification_nonce")

    image = Path("/home/user/alpine.sif")
    assert image.is_file(), "The requested Apptainer image was not created"
    inspected = run(["/usr/bin/apptainer", "inspect", str(image)], timeout=30)
    assert inspected.returncode == 0, f"alpine.sif is not a valid Apptainer image: {inspected.stderr}"

    observed_text = "\n".join(observed).lower()
    assert "ssh" in observed_text and "9999:localhost:8888" in observed_text, \
        "No live SSH local-forward process was observed"
    assert "apptainer" in observed_text and "metric_sandbox" in observed_text, \
        "No metric_sandbox Apptainer lifecycle was observed"
    assert "instance://metric_sandbox" in observed_text, \
        "Metric fetching was not observed executing inside the running instance"
    assert "expect" in observed_text, "An Expect process was not observed during the interaction"

    instances = run(["/usr/bin/apptainer", "instance", "list"])
    assert "metric_sandbox" not in instances.stdout, "The Apptainer instance was not stopped"
    tunnels = run(["pgrep", "-af", "ssh.*9999:localhost:8888"])
    remaining = [line for line in tunnels.stdout.splitlines() if "pgrep -af" not in line]
    assert not remaining, f"The SSH tunnel was not terminated: {remaining}"
PY

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
