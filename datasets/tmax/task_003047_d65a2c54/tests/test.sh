#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import secrets
import stat
import subprocess
import time
import pytest


def test_cpp_service_updated():
    cpp_path = "/home/user/service/main.cpp"
    assert os.path.isfile(cpp_path), f"File {cpp_path} is missing."
    with open(cpp_path, "r") as f:
        content = f.read()
    assert "/home/user/service/backend.sock" in content, "The C++ service was not updated to use the correct socket path."
    assert "/home/user/service/wrong.sock" not in content, "The C++ service still contains the wrong socket path."


def test_nginx_config():
    nginx_conf_path = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(nginx_conf_path), f"File {nginx_conf_path} is missing."
    with open(nginx_conf_path, "r") as f:
        content = f.read()

    # Check listening port
    assert re.search(r"listen\s+8080\s*;", content), "Nginx is not configured to listen on port 8080."

    # Check proxy pass
    assert re.search(r"proxy_pass\s+http://unix:/home/user/service/backend\.sock\s*;", content), "Nginx is not proxying to the correct backend.sock."

    # Check access control
    assert re.search(r"allow\s+127\.0\.0\.1\s*;", content), "Nginx config missing 'allow 127.0.0.1;'."
    assert re.search(r"deny\s+all\s*;", content), "Nginx config missing 'deny all;'."


def test_services_running():
    # Check processes
    ps_output = subprocess.check_output(["ps", "aux"], text=True)
    assert "nginx" in ps_output, "Nginx is not running."
    assert "socat" in ps_output, "socat is not running."
    assert "backend_service" in ps_output or "./backend_service" in ps_output or "main" in ps_output, "The C++ backend service is not running."

    # Check listening ports
    ss_output = subprocess.check_output(["ss", "-tln"], text=True)
    assert ":8080" in ss_output, "Nothing is listening on port 8080 (expected Nginx)."
    assert ":9090" in ss_output, "Nothing is listening on port 9090 (expected socat)."


def test_migration_status():
    target_path = "/home/user/data/migration_target.txt"
    status_path = "/home/user/data/migration_status.txt"

    assert os.path.isfile(target_path), f"File {target_path} is missing."
    with open(target_path, "r") as f:
        target_content = f.read().strip()

    assert os.path.isfile(status_path), f"File {status_path} is missing. The API was likely not triggered or the C++ service failed to write it."
    with open(status_path, "r") as f:
        status_content = f.read().strip()

    expected_status = f"MIGRATION_COMPLETE_TO_{target_content}"
    assert status_content == expected_status, f"Expected status '{expected_status}', but got '{status_content}'."


def test_test_result():
    result_path = "/home/user/test_result.txt"
    assert os.path.isfile(result_path), f"File {result_path} is missing. Did you save the curl output?"
    with open(result_path, "r") as f:
        content = f.read().strip()
    assert content == "Success", f"Expected test result to be 'Success', but got '{content}'."


def _pids_from_ss_line(line):
    return [int(pid) for pid in re.findall(r"pid=(\d+)", line)]


def _cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def test_runtime_artifacts_and_listener_owners():
    binary = "/home/user/service/backend_service"
    socket_path = "/home/user/service/backend.sock"

    assert os.path.isfile(binary), "The compiled backend_service binary is missing."
    assert os.access(binary, os.X_OK), "backend_service is not executable."
    assert os.path.exists(socket_path), "The required backend Unix socket is missing."
    assert stat.S_ISSOCK(os.stat(socket_path).st_mode), "backend.sock is not a Unix domain socket."

    tcp_output = subprocess.check_output(["ss", "-tlnp"], text=True)
    nginx_lines = [line for line in tcp_output.splitlines() if ":8080" in line]
    socat_lines = [line for line in tcp_output.splitlines() if ":9090" in line]
    assert any('"nginx"' in line for line in nginx_lines), "Port 8080 is not owned by Nginx."
    assert any('"socat"' in line for line in socat_lines), "Port 9090 is not owned by socat."

    nginx_pids = {pid for line in nginx_lines for pid in _pids_from_ss_line(line)}
    nginx_ps = subprocess.check_output(["ps", "-eo", "pid=,args="], text=True)
    assert "/home/user/nginx/nginx.conf" in nginx_ps and "nginx" in nginx_ps, "Nginx was not started with the required configuration file."

    socat_pids = {pid for line in socat_lines for pid in _pids_from_ss_line(line)}
    assert socat_pids, "Could not identify the socat process listening on port 9090."
    assert any("8080" in _cmdline(pid) for pid in socat_pids), "The socat listener on port 9090 is not forwarding to port 8080."

    unix_output = subprocess.check_output(["ss", "-xlpn"], text=True)
    backend_lines = [line for line in unix_output.splitlines() if socket_path in line]
    assert backend_lines, "No process is listening on backend.sock."
    backend_pids = {pid for line in backend_lines for pid in _pids_from_ss_line(line)}
    assert backend_pids, "Could not identify the process listening on backend.sock."
    expected_exe = os.path.realpath(binary)
    actual_exes = []
    for pid in backend_pids:
        try:
            actual_exes.append(os.path.realpath(f"/proc/{pid}/exe"))
        except OSError:
            pass
    assert expected_exe in actual_exes, "backend.sock is not owned by the compiled backend_service."


def _exercise_endpoint(target, curl_args):
    target_path = "/home/user/data/migration_target.txt"
    status_path = "/home/user/data/migration_status.txt"

    with open(target_path, "w") as f:
        f.write(target)
    try:
        os.unlink(status_path)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        ["curl", "--silent", "--show-error", "--fail", "--max-time", "5"] + curl_args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=8,
    )
    assert result.returncode == 0, f"HTTP request failed: {result.stderr.strip()}"
    assert result.stdout == "Success", f"Expected response body 'Success', got {result.stdout!r}."

    deadline = time.time() + 2
    while time.time() < deadline and not os.path.isfile(status_path):
        time.sleep(0.05)
    assert os.path.isfile(status_path), "The request did not create migration_status.txt."
    with open(status_path, "r") as f:
        actual = f.read()
    assert actual == f"MIGRATION_COMPLETE_TO_{target}", "The live backend did not derive migration_status.txt from the current target file."


def test_live_end_to_end_chain():
    target_path = "/home/user/data/migration_target.txt"
    status_path = "/home/user/data/migration_status.txt"
    with open(target_path, "rb") as f:
        original_target = f.read()
    original_status = None
    if os.path.isfile(status_path):
        with open(status_path, "rb") as f:
            original_status = f.read()

    try:
        # Exercise the compiled service over its required Unix socket.
        uds_target = "VERIFY_UDS_" + secrets.token_hex(12)
        _exercise_endpoint(
            uds_target,
            ["--unix-socket", "/home/user/service/backend.sock", "http://localhost/api/migrate"],
        )

        # Exercise Nginx and confirm it reaches the Unix-socket backend.
        nginx_target = "VERIFY_NGINX_" + secrets.token_hex(12)
        _exercise_endpoint(
            nginx_target,
            ["--noproxy", "*", "http://127.0.0.1:8080/api/migrate"],
        )

        # Exercise the required complete path: 9090 -> socat -> Nginx -> UDS backend.
        end_to_end_target = "VERIFY_END_TO_END_" + secrets.token_hex(12)
        _exercise_endpoint(
            end_to_end_target,
            ["--noproxy", "*", "http://127.0.0.1:9090/api/migrate"],
        )
    finally:
        with open(target_path, "wb") as f:
            f.write(original_target)
        if original_status is None:
            try:
                os.unlink(status_path)
            except FileNotFoundError:
                pass
        else:
            with open(status_path, "wb") as f:
                f.write(original_status)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
