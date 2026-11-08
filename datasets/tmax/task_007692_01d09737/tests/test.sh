#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess

APP_DIR = "/home/user/app"


def discovered_socket_path():
    discovery_log = "/home/user/app/discovery.log"
    assert os.path.isfile(discovery_log), f"{discovery_log} is missing."

    with open(discovery_log, "r") as f:
        content = f.read()

    match = re.search(r"BIND_ADDR=(\S+)", content)
    assert match is not None, "Could not find BIND_ADDR in discovery.log"
    return match.group(1)


def test_nginx_upstream_conf_content():
    socket_path = discovered_socket_path()

    conf_file = "/home/user/app/nginx-upstream.conf"
    assert os.path.isfile(conf_file), f"{conf_file} was not generated."

    with open(conf_file, "r") as f:
        conf_content = f.read().strip()

    expected_conf = f"upstream backend {{ server unix:{socket_path}; }}"
    assert conf_content == expected_conf, f"Expected '{expected_conf}', but got '{conf_content}' in {conf_file}"


def test_generator_was_modified_and_generates_configuration():
    socket_path = discovered_socket_path()
    script_file = "/home/user/app/generate_config.sh"
    conf_file = "/home/user/app/nginx-upstream.conf"

    assert os.path.isfile(script_file), f"{script_file} is missing."
    assert os.access(script_file, os.X_OK), f"{script_file} is not executable."

    with open(script_file, "r") as f:
        script_content = f.read()

    active_lines = [line for line in script_content.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    assert any(re.match(r"^\s*(?:export\s+)?SOCKET_PATH\s*=", line) for line in active_lines), \
        f"{script_file} does not set SOCKET_PATH."
    assert not any("/tmp/app.sock" in line for line in active_lines), \
        f"{script_file} still uses the old hardcoded socket path."

    original_conf = None
    if os.path.exists(conf_file):
        with open(conf_file, "rb") as f:
            original_conf = f.read()

    try:
        if os.path.lexists(conf_file):
            os.remove(conf_file)
        subprocess.run([script_file], cwd="/tmp", check=True, timeout=10)
        assert os.path.isfile(conf_file), f"Running {script_file} did not generate {conf_file}."
        with open(conf_file, "r") as f:
            generated = f.read().strip()
        expected = f"upstream backend {{ server unix:{socket_path}; }}"
        assert generated == expected, f"Running {script_file} generated {generated!r}, expected {expected!r}."
    finally:
        if os.path.lexists(conf_file):
            os.remove(conf_file)
        if original_conf is not None:
            with open(conf_file, "wb") as f:
                f.write(original_conf)


def test_daemon_log_rotated_old_content():
    old_log = "/home/user/app/daemon.log.1"
    assert os.path.isfile(old_log), f"{old_log} is missing. Did the rotation script run?"

    with open(old_log, "r") as f:
        content = f.read()

    assert "ERROR: Connection refused to" in content, f"{old_log} does not contain the expected old log content."


def test_daemon_log_new_content():
    new_log = "/home/user/app/daemon.log"
    assert os.path.isfile(new_log), f"{new_log} is missing."

    with open(new_log, "r") as f:
        content = f.read()

    assert content == "--- LOG ROTATED ---\n", f"Expected exactly '--- LOG ROTATED ---' (with newline) in {new_log}, got {repr(content)}"


def test_rotate_script_exists_and_executable():
    script_file = "/home/user/app/rotate.sh"
    assert os.path.isfile(script_file), f"{script_file} is missing."

    st = os.stat(script_file)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_file} is not executable."


def test_rotate_script_behavior():
    script_file = "/home/user/app/rotate.sh"
    new_log = "/home/user/app/daemon.log"
    old_log = "/home/user/app/daemon.log.1"

    assert os.path.isfile(script_file), f"{script_file} is missing."
    assert os.access(script_file, os.X_OK), f"{script_file} is not executable."

    with open(new_log, "rb") as f:
        saved_new = f.read()
    with open(old_log, "rb") as f:
        saved_old = f.read()

    token = secrets.token_hex(24)
    test_payload = f"rotation-test-{token}\nsecond-line-{token}\n".encode()

    try:
        with open(new_log, "wb") as f:
            f.write(test_payload)
        with open(old_log, "wb") as f:
            f.write(b"stale-rotated-log\n")

        subprocess.run([script_file], cwd="/tmp", check=True, timeout=10)

        assert os.path.isfile(old_log), f"{script_file} did not create {old_log}."
        with open(old_log, "rb") as f:
            rotated = f.read()
        assert rotated == test_payload, f"{script_file} did not rename the existing daemon.log unchanged."

        assert os.path.isfile(new_log), f"{script_file} did not create a new {new_log}."
        with open(new_log, "rb") as f:
            current = f.read()
        assert current == b"--- LOG ROTATED ---\n", \
            f"After rotation, {new_log} contained {current!r}."
    finally:
        for path in (new_log, old_log):
            if os.path.lexists(path):
                os.remove(path)
        with open(new_log, "wb") as f:
            f.write(saved_new)
        with open(old_log, "wb") as f:
            f.write(saved_old)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
