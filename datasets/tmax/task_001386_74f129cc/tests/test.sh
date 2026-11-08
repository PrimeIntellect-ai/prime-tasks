#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import socket
import stat
import subprocess
import threading
import time


def compute_wer(ref, hyp):
    """Computes Word Error Rate (WER) between reference and hypothesis strings."""
    ref = re.sub(r'[^\w\s]', '', ref.lower()).split()
    hyp = re.sub(r'[^\w\s]', '', hyp.lower()).split()

    d = [[0] * (len(hyp) + 1) for _ in range(len(ref) + 1)]
    for i in range(len(ref) + 1):
        d[i][0] = i
    for j in range(len(hyp) + 1):
        d[0][j] = j

    for i in range(1, len(ref) + 1):
        for j in range(1, len(hyp) + 1):
            if ref[i - 1] == hyp[j - 1]:
                d[i][j] = d[i - 1][j - 1]
            else:
                substitution = d[i - 1][j - 1] + 1
                insertion = d[i][j - 1] + 1
                deletion = d[i - 1][j] + 1
                d[i][j] = min(substitution, insertion, deletion)

    if len(ref) == 0:
        return float('inf')
    return d[len(ref)][len(hyp)] / len(ref)


def run_monitor(path, port, timeout):
    return subprocess.run(
        [path, str(port), str(timeout)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout + 4,
    )


def exercise_monitor(path):
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    port = listener.getsockname()[1]

    def accept_once():
        try:
            conn, _ = listener.accept()
            conn.close()
        finally:
            listener.close()

    thread = threading.Thread(target=accept_once, daemon=True)
    thread.start()
    healthy = run_monitor(path, port, 2)
    thread.join(timeout=3)
    assert healthy.returncode == 0, (
        f"{path} failed against a listening TCP server: "
        f"stdout={healthy.stdout!r}, stderr={healthy.stderr!r}, rc={healthy.returncode}"
    )
    assert healthy.stdout.strip() == "HEALTHY", f"Unexpected healthy output: {healthy.stdout!r}"

    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.bind(("127.0.0.1", 0))
    closed_port = probe.getsockname()[1]
    probe.close()
    unhealthy = run_monitor(path, closed_port, 1)
    assert unhealthy.returncode == 1, (
        f"{path} did not return 1 for a closed port: "
        f"stdout={unhealthy.stdout!r}, stderr={unhealthy.stderr!r}, rc={unhealthy.returncode}"
    )
    assert unhealthy.stdout.strip() == "UNHEALTHY", f"Unexpected unhealthy output: {unhealthy.stdout!r}"


def kill_port_listeners(port):
    """Kill pre-existing processes listening on the deployment port."""
    wanted = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    inode = fields[9]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        wanted.add(inode)
        except FileNotFoundError:
            pass

    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in wanted:
                    try:
                        os.kill(int(pid), 9)
                    except ProcessLookupError:
                        pass
                    break
        except (FileNotFoundError, PermissionError):
            pass
    time.sleep(0.2)


def run_deploy(script_path):
    return subprocess.run(
        ["bash", script_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=12,
    )


def test_transcription_accuracy():
    """Check that the transcription meets the WER threshold."""
    transcript_path = "/home/user/transcript.txt"
    assert os.path.isfile(transcript_path), f"Transcript file {transcript_path} is missing."

    with open(transcript_path, "r") as f:
        hyp = f.read().strip()

    ref = "Please update the mailing list server to use port eight zero two five and set the health check timeout to four seconds."

    wer = compute_wer(ref, hyp)
    assert wer <= 0.2, f"Word Error Rate {wer:.2f} exceeds the threshold of 0.2. Transcript was: '{hyp}'"


def test_health_monitor_executable():
    """Check and execute both the submitted binary and the submitted C source."""
    monitor_path = "/home/user/health_monitor"
    source_path = "/home/user/health_monitor.c"
    assert os.path.isfile(monitor_path), f"Health monitor executable {monitor_path} is missing."
    assert os.access(monitor_path, os.X_OK), f"Health monitor {monitor_path} is not executable."
    assert os.path.isfile(source_path), f"Health monitor source {source_path} is missing."

    with open(monitor_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Health monitor is not a compiled ELF executable."

    compiled_path = "/tmp/health_monitor_from_source"
    build = subprocess.run(
        ["gcc", source_path, "-o", compiled_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert build.returncode == 0, f"health_monitor.c does not compile with gcc: {build.stderr}"

    exercise_monitor(monitor_path)
    exercise_monitor(compiled_path)


def test_deploy_script_exists():
    """Check that the deployment script exists."""
    script_path = "/home/user/deploy.sh"
    assert os.path.isfile(script_path), f"Deployment script {script_path} is missing."


def test_deploy_log_success():
    """Keep the original assertion that the requested deployment was executed."""
    log_path = "/home/user/deploy.log"
    assert os.path.isfile(log_path), f"Deployment log {log_path} is missing."

    with open(log_path, "r") as f:
        log_content = f.read()

    assert "DEPLOYMENT SUCCESS" in log_content, f"Deployment log does not contain 'DEPLOYMENT SUCCESS'. Log content: {log_content}"


def test_deploy_script_behavior():
    """Execute the deployment and verify listener startup, monitor arguments, and both branches."""
    script_path = "/home/user/deploy.sh"
    monitor_path = "/home/user/health_monitor"
    log_path = "/home/user/deploy.log"
    backup_path = "/tmp/original_health_monitor"
    invocation_path = "/tmp/verifier_monitor_invocation"
    mode_path = "/tmp/verifier_monitor_mode"

    # First run the submitted deployment with the real submitted monitor.
    kill_port_listeners(8025)
    if os.path.exists(log_path):
        os.remove(log_path)
    real_run = run_deploy(script_path)
    assert os.path.isfile(log_path), "Running deploy.sh did not create deploy.log."
    with open(log_path) as f:
        real_log = f.read()
    assert "DEPLOYMENT SUCCESS" in real_log, (
        f"Running deploy.sh with the real monitor did not succeed. Log={real_log!r}, "
        f"stdout={real_run.stdout!r}, stderr={real_run.stderr!r}"
    )

    shutil.copy2(monitor_path, backup_path)
    wrapper = '''#!/usr/bin/env python3
import os
import socket
import sys
import time

with open("/tmp/verifier_monitor_invocation", "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\\n")

args_ok = sys.argv[1:] == ["8025", "4"]
connected = False
end = time.time() + 3.0
while time.time() < end:
    try:
        with socket.create_connection(("127.0.0.1", 8025), timeout=0.25):
            connected = True
            break
    except OSError:
        time.sleep(0.05)

mode = open("/tmp/verifier_monitor_mode").read().strip()
if args_ok and connected and mode == "healthy":
    print("HEALTHY")
    sys.exit(0)
print("UNHEALTHY")
sys.exit(1)
'''

    try:
        with open(monitor_path, "w") as f:
            f.write(wrapper)
        os.chmod(monitor_path, 0o755)

        for mode, expected, forbidden in (
            ("healthy", "DEPLOYMENT SUCCESS", "DEPLOYMENT FAILED"),
            ("failure", "DEPLOYMENT FAILED", "DEPLOYMENT SUCCESS"),
        ):
            kill_port_listeners(8025)
            for path in (log_path, invocation_path):
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            with open(mode_path, "w") as f:
                f.write(mode)

            result = run_deploy(script_path)
            assert os.path.isfile(invocation_path), (
                f"deploy.sh did not call /home/user/health_monitor in {mode} test. "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
            with open(invocation_path) as f:
                invocations = [line.strip() for line in f if line.strip()]
            assert "8025 4" in invocations, f"Monitor was not called with port 8025 and timeout 4: {invocations}"
            assert os.path.isfile(log_path), f"deploy.sh did not create deploy.log in {mode} test."
            with open(log_path) as f:
                content = f.read()
            assert expected in content, f"Expected {expected!r} after {mode} result; log was {content!r}"
            assert forbidden not in content, f"deploy.sh logged {forbidden!r} for the {mode} result: {content!r}"
    finally:
        if os.path.exists(backup_path):
            shutil.copy2(backup_path, monitor_path)
        kill_port_listeners(8025)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
