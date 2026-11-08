#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PYEOF' > /tmp/test_final_state.py
import os
import re
import socket
import subprocess
import time
from pathlib import Path

import pytest

FAST_SCRIPT = "/home/user/fast_provision.py"
TRACE = Path("/tmp/verifier_pexpect_trace")
ADMIN_TRACE = Path("/tmp/verifier_admin_trace")
READY_DIR = Path("/tmp/verifier_ready")


def stop_services():
    subprocess.run(["redis-cli", "-p", "6379", "shutdown", "nosave"], capture_output=True)
    for pattern in ("/tmp/verifier_auth_api.py", "/tmp/verifier_worker.py", "redis-server"):
        subprocess.run(["pkill", "-f", pattern], capture_output=True)
    deadline = time.time() + 2
    while time.time() < deadline:
        busy = False
        for port in (6379, 8080):
            with socket.socket() as s:
                s.settimeout(0.05)
                if s.connect_ex(("127.0.0.1", port)) == 0:
                    busy = True
        if not busy:
            break
        time.sleep(0.05)
    try:
        os.remove("/tmp/worker_health.sock")
    except FileNotFoundError:
        pass


def install_instrumentation(tmp_path):
    site = tmp_path / "sitecustomize.py"
    site.write_text(r'''
import os
try:
    import pexpect
    _OriginalSpawn = pexpect.spawn
    _trace = os.environ.get("VERIFIER_PEXPECT_TRACE")

    def _write(line):
        if _trace:
            with open(_trace, "a", encoding="utf-8") as f:
                f.write(line + "\n")

    class TrackedSpawn(_OriginalSpawn):
        def __init__(self, command, args=[], *a, **kw):
            _write("SPAWN:" + repr(command) + ":" + repr(args))
            super().__init__(command, args, *a, **kw)

        def expect(self, pattern, *a, **kw):
            _write("EXPECT:" + repr(pattern))
            return super().expect(pattern, *a, **kw)

        def expect_exact(self, pattern, *a, **kw):
            _write("EXPECT_EXACT:" + repr(pattern))
            return super().expect_exact(pattern, *a, **kw)

        def send(self, data):
            raw = data if isinstance(data, bytes) else str(data).encode("utf-8")
            _write("SEND:" + raw.hex())
            return super().send(data)

    pexpect.spawn = TrackedSpawn
except Exception:
    pass
''')

    Path("/app/admin_cli.py").write_text(r'''#!/usr/bin/env python3
import os
import socket
import sys
import time


def ready():
    with socket.create_connection(("127.0.0.1", 6379), timeout=1):
        pass
    with socket.create_connection(("127.0.0.1", 8080), timeout=1):
        pass
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(1)
        s.connect("/tmp/worker_health.sock")

if len(sys.argv) > 1 and sys.argv[1] == "init-cluster":
    try:
        ready()
    except Exception:
        print("Services are not ready.")
        sys.exit(2)
    with open(os.environ["VERIFIER_ADMIN_TRACE"], "w") as f:
        f.write(str(time.time()))
    user = input("Enter admin username: ")
    pwd = input("Enter admin password: ")
    conf = input("Confirm [y/N]: ")
    if user == "admin" and pwd == "supersecret" and conf.lower() == "y":
        print("Cluster initialized successfully.")
        sys.exit(0)
    print("Failed.")
    sys.exit(1)
''')
    os.chmod("/app/admin_cli.py", 0o755)

    Path("/tmp/verifier_auth_api.py").write_text(r'''import os, socket, time
time.sleep(float(os.environ["D_AUTH"]))
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 8080)); s.listen(20)
open("/tmp/verifier_ready/auth", "w").write(str(time.time()))
while True:
    c, _ = s.accept()
    try:
        c.recv(4096)
        c.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK")
    except Exception: pass
    c.close()
''')
    Path("/tmp/verifier_worker.py").write_text(r'''import os, socket, time
time.sleep(float(os.environ["D_WORKER"]))
p = "/tmp/worker_health.sock"
try: os.remove(p)
except FileNotFoundError: pass
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.bind(p); s.listen(20)
open("/tmp/verifier_ready/worker", "w").write(str(time.time()))
while True:
    c, _ = s.accept()
    try: c.sendall(b"OK")
    except Exception: pass
    c.close()
''')

    Path("/app/start_services.sh").write_text(r'''#!/bin/bash
set -e
mkdir -p /tmp/verifier_ready
(
  sleep "$D_REDIS"
  redis-server --daemonize yes
  until redis-cli -p 6379 ping >/dev/null 2>&1; do sleep 0.02; done
  date +%s.%N > /tmp/verifier_ready/redis
) >/dev/null 2>&1 &
python3 /tmp/verifier_auth_api.py >/dev/null 2>&1 &
python3 /tmp/verifier_worker.py >/dev/null 2>&1 &
''')
    os.chmod("/app/start_services.sh", 0o755)
    return site.parent


def assert_pexpect_trace():
    assert TRACE.is_file(), "No runtime pexpect activity was recorded"
    text = TRACE.read_text()
    assert "SPAWN:" in text and "admin_cli.py" in text and "init-cluster" in text, \
        "admin_cli.py init-cluster was not launched through pexpect.spawn"
    expects = "\n".join(line for line in text.splitlines() if line.startswith(("EXPECT:", "EXPECT_EXACT:")))
    for prompt_fragment in ("username", "password", "Confirm"):
        assert prompt_fragment.lower() in expects.lower(), f"pexpect did not wait for the {prompt_fragment} prompt"
    sent = b"".join(bytes.fromhex(line[5:]) for line in text.splitlines() if line.startswith("SEND:"))
    assert re.search(br"admin\r?\n.*supersecret\r?\n.*y\r?\n", sent, re.S), \
        "pexpect did not send the required interactive answers"


def run_trial(site_dir, delays):
    stop_services()
    READY_DIR.mkdir(exist_ok=True)
    for p in READY_DIR.iterdir():
        p.unlink()
    for p in (TRACE, ADMIN_TRACE, Path("/home/user/provision.log")):
        try: p.unlink()
        except FileNotFoundError: pass

    env = os.environ.copy()
    env.update({
        "D_REDIS": str(delays["redis"]),
        "D_AUTH": str(delays["auth"]),
        "D_WORKER": str(delays["worker"]),
        "VERIFIER_PEXPECT_TRACE": str(TRACE),
        "VERIFIER_ADMIN_TRACE": str(ADMIN_TRACE),
        "PYTHONPATH": str(site_dir) + (":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""),
    })
    start = time.time()
    result = subprocess.run([FAST_SCRIPT], capture_output=True, text=True, env=env, timeout=8)
    duration = time.time() - start
    assert result.returncode == 0, f"fast_provision.py failed with return code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    assert duration <= 6.0, f"Speedup metric failed: fast_provision.py took {duration:.2f}s (must be <= 6.0s)."

    for name in ("redis", "auth", "worker"):
        assert (READY_DIR / name).is_file(), f"The {name} service never became ready"
    assert ADMIN_TRACE.is_file(), "admin_cli.py init-cluster was not actually executed"
    ready_at = max(float((READY_DIR / name).read_text()) for name in ("redis", "auth", "worker"))
    admin_at = float(ADMIN_TRACE.read_text())
    assert admin_at >= ready_at, "admin_cli.py was executed before every service was responsive"
    assert admin_at - ready_at <= 0.70, \
        f"admin_cli.py was started {admin_at - ready_at:.2f}s after readiness; provisioning is not actively polling"
    assert_pexpect_trace()


def test_fast_provision_executable():
    assert os.path.isfile(FAST_SCRIPT), f"Missing file: {FAST_SCRIPT}"
    assert os.access(FAST_SCRIPT, os.X_OK), f"File is not executable: {FAST_SCRIPT}"


def test_provisioning_speedup_success_polling_and_pexpect(tmp_path):
    site_dir = install_instrumentation(tmp_path)
    # Make a different service the final dependency in each run, while varying
    # the overall readiness time so one fixed delay cannot satisfy the test.
    run_trial(site_dir, {"redis": 0.80, "auth": 0.15, "worker": 0.15})
    run_trial(site_dir, {"redis": 0.15, "auth": 1.50, "worker": 0.15})
    run_trial(site_dir, {"redis": 0.15, "auth": 0.15, "worker": 2.30})


def test_services_running():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1)
        assert s.connect_ex(("127.0.0.1", 6379)) == 0, "Redis is not listening on port 6379"
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1)
        assert s.connect_ex(("127.0.0.1", 8080)) == 0, "Auth API is not listening on port 8080"
    assert os.path.exists("/tmp/worker_health.sock"), "Worker health socket /tmp/worker_health.sock does not exist"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(1)
        assert s.connect_ex("/tmp/worker_health.sock") == 0, "Cannot connect to Worker health socket"


def test_provision_log():
    path = Path("/home/user/provision.log")
    assert path.is_file(), f"Log file missing: {path}"
    content = path.read_text().replace("\r\n", "\n")
    program_output = "Enter admin username: Enter admin password: Confirm [y/N]: Cluster initialized successfully.\n"
    pty_transcript = "Enter admin username: admin\nEnter admin password: supersecret\nConfirm [y/N]: y\nCluster initialized successfully.\n"
    assert content in (program_output, pty_transcript), \
        f"provision.log is not the exact admin_cli.py output/transcript. Found: {content!r}"


def test_crontab_configured():
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab"
    expected_cron = "*/5 * * * * /app/health_check.py"
    assert expected_cron in result.stdout, f"Crontab does not contain the expected entry. Found:\n{result.stdout}"
PYEOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
