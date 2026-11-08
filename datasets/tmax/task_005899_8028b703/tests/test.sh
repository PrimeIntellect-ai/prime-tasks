#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import socket
import subprocess
import time
import urllib.request
import pytest

BACKEND = "/home/user/backend/server"
SOURCE = "/home/user/backend/server.cpp"
EXPECT_SCRIPT = "/home/user/backend/start.exp"
EXPECTED_BODY = b"Backend OK!\n"


def http_get(url, timeout=2):
    request = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.status, response.version, response.headers, response.read()


def kill_listeners(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        if fields[1].rsplit(":", 1)[1].upper() == wanted:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

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
                    os.kill(int(pid), signal.SIGTERM)
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass

    deadline = time.time() + 3
    while time.time() < deadline:
        with socket.socket() as sock:
            if sock.connect_ex(("127.0.0.1", port)) != 0:
                return
        time.sleep(0.1)


def listener_is_ipv4_loopback(port):
    wanted = f"{port:04X}"
    try:
        with open("/proc/net/tcp") as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 4 and fields[3] == "0A":
                    address, found_port = fields[1].split(":")
                    if found_port.upper() == wanted and address.upper() == "0100007F":
                        return True
    except FileNotFoundError:
        pass
    return False


def wait_for_http(url, timeout=8):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            return http_get(url)
        except Exception as exc:
            last_error = exc
            time.sleep(0.15)
    pytest.fail(f"Service at {url} did not become ready: {last_error}")


def test_backup_exists_and_correct():
    backup_path = "/home/user/backup/nginx.conf.bak"
    assert os.path.isfile(backup_path), f"Backup file {backup_path} does not exist."
    with open(backup_path, "r") as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:9001;" in content, \
        "Backup file does not contain the original proxy_pass directive (9001)."


def test_nginx_config_fixed():
    nginx_conf_path = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(nginx_conf_path), f"Nginx config {nginx_conf_path} does not exist."
    with open(nginx_conf_path, "r") as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:9000;" in content, \
        "Nginx config was not updated to proxy_pass to port 9000."


def test_compiled_backend_exists():
    assert os.path.isfile(BACKEND), f"Compiled backend binary {BACKEND} does not exist."
    assert os.access(BACKEND, os.X_OK), f"Compiled backend binary {BACKEND} is not executable."


def test_expect_script_exists():
    assert os.path.isfile(EXPECT_SCRIPT), f"Expect script {EXPECT_SCRIPT} does not exist."


def test_result_log_content():
    log_path = "/home/user/result.log"
    assert os.path.isfile(log_path), f"Result log {log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read()
    assert content == "Backend OK!\n", \
        f"Result log content is incorrect. Expected 'Backend OK!\\n', got {content!r}"


def test_nginx_process_running():
    try:
        output = subprocess.check_output(["ps", "aux"]).decode("utf-8")
        assert "nginx" in output and "-p /home/user/nginx" in output, \
            "Nginx is not running with the correct prefix."
    except subprocess.CalledProcessError:
        pytest.fail("Failed to check running processes.")


def test_backend_process_running_on_port_9000():
    try:
        output = subprocess.check_output(["ss", "-tlnp"]).decode("utf-8")
        assert ":9000" in output, "No process is listening on port 9000."
    except subprocess.CalledProcessError:
        pytest.fail("Failed to check listening ports.")


def test_live_nginx_pipeline():
    status, _, _, body = http_get("http://127.0.0.1:8080/api")
    assert status == 200
    assert body == EXPECTED_BODY, f"Unexpected response through Nginx: {body!r}"


def test_expect_script_source_and_backend_pipeline():
    assert os.path.isfile(SOURCE), f"Backend source {SOURCE} does not exist."

    # First execute the submitted Expect script against an instrumented program at
    # the required backend path. This proves it launches that path, waits for its
    # prompt, and supplies the PIN rather than merely existing as an empty file.
    kill_listeners(9000)
    os.unlink(BACKEND)
    pin_log = "/tmp/verifier_pin.txt"
    try:
        os.unlink(pin_log)
    except FileNotFoundError:
        pass

    with open(BACKEND, "w") as f:
        f.write("#!/usr/bin/python3\n"
                "import sys, time\n"
                "sys.stdout.write('Enter PIN: ')\n"
                "sys.stdout.flush()\n"
                "pin = sys.stdin.readline()\n"
                "open('/tmp/verifier_pin.txt', 'w').write(pin)\n"
                "time.sleep(0.5)\n")
    os.chmod(BACKEND, 0o755)

    expect_run = subprocess.Popen(
        ["expect", EXPECT_SCRIPT],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 6
    while time.time() < deadline and not os.path.exists(pin_log):
        if expect_run.poll() is not None and not os.path.exists(pin_log):
            break
        time.sleep(0.1)
    assert os.path.isfile(pin_log), "Expect script did not launch the required backend and submit input."
    with open(pin_log) as f:
        supplied_pin = f.read().strip()
    assert supplied_pin == "7788", f"Expect script supplied the wrong PIN: {supplied_pin!r}"
    try:
        expect_run.wait(timeout=3)
    except subprocess.TimeoutExpired:
        expect_run.terminate()
        expect_run.wait(timeout=2)

    # Compile the submitted source into the required artifact, then launch that
    # artifact through the submitted Expect script and exercise its HTTP behavior.
    os.unlink(BACKEND)
    compile_result = subprocess.run(
        ["g++", SOURCE, "-o", BACKEND],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, f"server.cpp does not compile:\n{compile_result.stderr}"
    assert os.access(BACKEND, os.X_OK)

    backend_launcher = subprocess.Popen(
        ["expect", EXPECT_SCRIPT],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    status, version, headers, body = wait_for_http("http://127.0.0.1:9000/")
    assert status == 200
    assert version == 11, "Backend did not return an HTTP/1.1 response."
    assert headers.get("Content-Length") == "12"
    assert body == EXPECTED_BODY, f"Compiled backend returned {body!r}"
    assert listener_is_ipv4_loopback(9000), \
        "Compiled backend is not bound specifically to IPv4 loopback 127.0.0.1:9000."

    # Recheck the complete live path after rebuilding from the submitted source and
    # launching it with the submitted Expect script.
    status, _, _, body = wait_for_http("http://127.0.0.1:8080/api")
    assert status == 200
    assert body == EXPECTED_BODY, f"Rebuilt backend failed through Nginx: {body!r}"


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
