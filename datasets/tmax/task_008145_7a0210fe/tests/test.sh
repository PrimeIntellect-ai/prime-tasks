#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess

NGINX_CONF_PATH = "/home/user/app/nginx.conf"
BACKEND_ENV_PATH = "/home/user/app/backend.env"
MONITOR_SCRIPT_PATH = "/home/user/monitor.sh"
METRICS_LOG_PATH = "/home/user/app/metrics.log"
EXPECTED_SOCKET_PATH = "/home/user/run/production_backend.sock"


def run_monitor():
    result = subprocess.run([MONITOR_SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Monitor script failed to execute. stderr: {result.stderr}"
    assert os.path.exists(METRICS_LOG_PATH), f"Monitor script did not create/write to {METRICS_LOG_PATH}."


def set_proxy_socket(content, socket_path):
    modified, count = re.subn(
        r'proxy_pass\s+http://unix:[^;]+;',
        f'proxy_pass http://unix:{socket_path};',
        content,
    )
    assert count >= 1, "Could not find a Unix-socket proxy_pass directive in nginx.conf"
    return modified


def read_log_lines():
    with open(METRICS_LOG_PATH, "r") as f:
        return f.read().splitlines()


def test_nginx_conf_updated():
    assert os.path.exists(NGINX_CONF_PATH), f"{NGINX_CONF_PATH} does not exist."
    with open(NGINX_CONF_PATH, "r") as f:
        content = f.read()

    expected_directive = f"proxy_pass http://unix:{EXPECTED_SOCKET_PATH};"
    assert expected_directive in content, f"Nginx configuration was not updated correctly. Expected to find: {expected_directive}"


def test_monitor_script_exists_and_executable():
    assert os.path.exists(MONITOR_SCRIPT_PATH), f"{MONITOR_SCRIPT_PATH} does not exist."
    st = os.stat(MONITOR_SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"{MONITOR_SCRIPT_PATH} is not executable."


def test_monitor_script_healthy_behavior():
    if os.path.exists(METRICS_LOG_PATH):
        os.remove(METRICS_LOG_PATH)

    run_monitor()

    expected_log = f"STATUS: HEALTHY - {EXPECTED_SOCKET_PATH}"
    log_lines = read_log_lines()
    assert log_lines == [expected_log], f"Expected exactly one line '{expected_log}' in {METRICS_LOG_PATH}, but got: {log_lines}"


def test_monitor_script_unhealthy_behavior():
    fake_socket = "/home/user/run/non_existent.sock"

    with open(NGINX_CONF_PATH, "r") as f:
        original_conf = f.read()

    modified_conf = set_proxy_socket(original_conf, fake_socket)

    try:
        if os.path.exists(fake_socket):
            os.remove(fake_socket)
        if os.path.exists(METRICS_LOG_PATH):
            os.remove(METRICS_LOG_PATH)

        with open(NGINX_CONF_PATH, "w") as f:
            f.write(modified_conf)

        run_monitor()

        expected_log = f"STATUS: UNHEALTHY - {fake_socket}"
        log_lines = read_log_lines()
        assert log_lines == [expected_log], f"Expected exactly one line '{expected_log}' in {METRICS_LOG_PATH}, but got: {log_lines}"
    finally:
        with open(NGINX_CONF_PATH, "w") as f:
            f.write(original_conf)


def test_monitor_parses_dynamic_paths_and_appends_one_line():
    token = secrets.token_hex(12)
    healthy_socket = f"/home/user/run/health_{token}.sock"
    unhealthy_socket = f"/home/user/run/missing_{token}.sock"
    sentinel = f"PREEXISTING-{secrets.token_hex(12)}"

    with open(NGINX_CONF_PATH, "r") as f:
        original_conf = f.read()

    try:
        with open(healthy_socket, "w"):
            pass
        with open(NGINX_CONF_PATH, "w") as f:
            f.write(set_proxy_socket(original_conf, healthy_socket))
        with open(METRICS_LOG_PATH, "w") as f:
            f.write(sentinel + "\n")

        run_monitor()
        expected_healthy = f"STATUS: HEALTHY - {healthy_socket}"
        assert read_log_lines() == [sentinel, expected_healthy], \
            "The monitor must append exactly one HEALTHY line for the socket parsed from nginx.conf"

        if os.path.exists(unhealthy_socket):
            os.remove(unhealthy_socket)
        with open(NGINX_CONF_PATH, "w") as f:
            f.write(set_proxy_socket(original_conf, unhealthy_socket))
        with open(METRICS_LOG_PATH, "w") as f:
            f.write(sentinel + "\n")

        run_monitor()
        expected_unhealthy = f"STATUS: UNHEALTHY - {unhealthy_socket}"
        assert read_log_lines() == [sentinel, expected_unhealthy], \
            "The monitor must append exactly one UNHEALTHY line for the socket parsed from nginx.conf"
    finally:
        with open(NGINX_CONF_PATH, "w") as f:
            f.write(original_conf)
        if os.path.exists(healthy_socket):
            os.remove(healthy_socket)
        if os.path.exists(unhealthy_socket):
            os.remove(unhealthy_socket)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
