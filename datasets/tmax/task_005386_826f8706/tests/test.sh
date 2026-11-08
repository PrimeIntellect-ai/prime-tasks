#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import signal
import subprocess
import time
import urllib.request
import uuid

import pytest

REPORT = "/home/user/ci_report.json"
PIPELINE = "/home/user/ci_pipeline.py"
CONF = "/home/user/nginx.conf"


def read_report():
    assert os.path.isfile(REPORT), f"CI report {REPORT} does not exist."
    with open(REPORT, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("CI report is not valid JSON.")
    assert set(data) == {"backend_ok", "static_ok", "symlink_valid"}, "CI report has an incorrect schema."
    assert all(type(data[k]) is bool for k in data), "CI report values must be JSON booleans."
    return data


def run_pipeline(timeout=15):
    if os.path.exists(REPORT):
        os.unlink(REPORT)
    try:
        result = subprocess.run(
            ["runuser", "-u", "user", "--", "python3", PIPELINE],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("ci_pipeline.py did not finish within the timeout.")
    assert result.returncode == 0, f"ci_pipeline.py failed:\n{result.stdout}\n{result.stderr}"
    return read_report()


def listener_inodes(port):
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                found.add(fields[9])
    return found


def listener_processes(port):
    inodes = listener_inodes(port)
    owners = []
    for proc in pathlib.Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                target = os.readlink(fd)
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    cmd = (proc / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
                    exe = os.readlink(proc / "exe")
                    owners.append((int(proc.name), exe, cmd))
                    break
        except (OSError, PermissionError):
            pass
    return owners


def wait_for_port(port, present, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if bool(listener_inodes(port)) == present:
            return
        time.sleep(0.1)
    pytest.fail(f"Port {port} did not become {'available' if present else 'closed'} in time.")


def stop_nginx():
    pid_path = "/home/user/nginx.pid"
    assert os.path.isfile(pid_path), "Nginx PID file is missing."
    pid = int(pathlib.Path(pid_path).read_text().strip())
    os.kill(pid, signal.SIGTERM)
    wait_for_port(8080, False)


def start_nginx():
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "/usr/sbin/nginx", "-c", CONF],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"Could not restart Nginx: {result.stderr}"
    wait_for_port(8080, True)


def fetch(url):
    with urllib.request.urlopen(url, timeout=5) as response:
        return response.getcode(), response.read().decode("utf-8")


def test_ci_report():
    data = read_report()
    assert data.get("backend_ok") is True, "backend_ok is not true in CI report."
    assert data.get("static_ok") is True, "static_ok is not true in CI report."
    assert data.get("symlink_valid") is True, "symlink_valid is not true in CI report."


def test_symlink_fixed():
    symlink_path = "/home/user/web_root/public"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."
    target = os.readlink(symlink_path)
    assert target == "/home/user/app/static", f"Symlink points to {target}, expected /home/user/app/static."
    assert os.path.isdir(symlink_path), f"Symlink {symlink_path} does not resolve to a valid directory."


def test_required_programs_are_running():
    nginx_owners = listener_processes(8080)
    assert nginx_owners, "Nothing is listening on port 8080."
    assert any(os.path.basename(exe) == "nginx" for _, exe, _ in nginx_owners), "Port 8080 is not owned by Nginx."
    assert any(os.path.basename(exe) == "nginx" and "-c /home/user/nginx.conf" in cmd for _, exe, cmd in nginx_owners), \
        "The Nginx listener was not started with /home/user/nginx.conf."

    backend_owners = listener_processes(9001)
    assert backend_owners, "Nothing is listening on the backend port 9001."
    assert any("python" in os.path.basename(exe) and "/home/user/app/server.py" in cmd for _, exe, cmd in backend_owners), \
        "Port 9001 is not served by /home/user/app/server.py."


def test_live_endpoints():
    try:
        status, body = fetch("http://127.0.0.1:8080/")
        assert status == 200, f"Expected status 200 for backend, got {status}"
        assert "Backend is alive" in body, "Backend response does not contain 'Backend is alive'."
    except Exception as e:
        pytest.fail(f"Failed to connect to backend via Nginx: {e}")

    try:
        status, body = fetch("http://127.0.0.1:8080/static/index.html")
        assert status == 200, f"Expected status 200 for static file, got {status}"
        assert "Hello from static" in body, "Static response does not contain 'Hello from static'."
    except Exception as e:
        pytest.fail(f"Failed to connect to static file via Nginx: {e}")

    name = f"verifier-{uuid.uuid4().hex}.txt"
    path = pathlib.Path("/home/user/app/static") / name
    token = f"dynamic-{uuid.uuid4().hex}"
    path.write_text(token)
    try:
        status, body = fetch(f"http://127.0.0.1:8080/static/{name}")
        assert status == 200 and body == token, "Nginx is not serving dynamic files from the required static directory."
        status, body = fetch(f"http://127.0.0.1:8080/probe-{uuid.uuid4().hex}")
        assert status == 200 and "Backend is alive" in body, "Nginx is not proxying arbitrary paths to the backend."
    finally:
        path.unlink(missing_ok=True)


def test_ci_pipeline_exists_and_reacts_to_results():
    assert os.path.isfile(PIPELINE), f"Required pipeline {PIPELINE} does not exist."
    assert not os.path.islink(PIPELINE), "ci_pipeline.py must be a real Python script, not a symlink."
    compile(pathlib.Path(PIPELINE).read_text(), PIPELINE, "exec")

    data = run_pipeline()
    assert data == {"backend_ok": True, "static_ok": True, "symlink_valid": True}

    static_file = pathlib.Path("/home/user/app/static/index.html")
    original = static_file.read_bytes()
    try:
        static_file.write_text("content without the required marker")
        data = run_pipeline()
        assert data["backend_ok"] is True, "Pipeline incorrectly failed the healthy backend check."
        assert data["static_ok"] is False, "Pipeline did not detect an invalid static response."
        assert data["symlink_valid"] is True, "Pipeline incorrectly failed the valid symlink check."
    finally:
        static_file.write_bytes(original)

    stopped = False
    try:
        stop_nginx()
        stopped = True
        data = run_pipeline()
        assert data["backend_ok"] is False, "Pipeline did not detect that the backend proxy was unavailable."
        assert data["static_ok"] is False, "Pipeline did not detect that the static endpoint was unavailable."
        assert data["symlink_valid"] is True, "Pipeline incorrectly failed the valid symlink check."
    finally:
        if stopped and not listener_inodes(8080):
            start_nginx()

    data = run_pipeline()
    assert data == {"backend_ok": True, "static_ok": True, "symlink_valid": True}
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
