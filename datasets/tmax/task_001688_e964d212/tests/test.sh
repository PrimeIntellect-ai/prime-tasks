#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import socket
import subprocess
import tempfile
import threading
import uuid

import pytest

SCRIPT_PATH = "/home/user/update_config.sh"
SERVER_CONF = "/home/user/app/server.conf"
PROXY_CONF = "/home/user/deploy/proxy.conf"
SOURCE_PATH = "/home/user/health_check.cpp"
HCHECK_PATH = "/home/user/hcheck"
LOG_PATH = "/home/user/health_report.log"


def read_bind_path():
    with open(SERVER_CONF, "r") as f:
        for line in f:
            if line.startswith("BIND_PATH="):
                return line.strip().split("=", 1)[1]
    return None


def test_update_config_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."


def test_proxy_conf_updated():
    assert os.path.isfile(SERVER_CONF), f"{SERVER_CONF} does not exist."
    assert os.path.isfile(PROXY_CONF), f"{PROXY_CONF} does not exist."

    bind_path = read_bind_path()
    assert bind_path is not None, "BIND_PATH not found in server.conf"

    with open(PROXY_CONF, "r") as f:
        proxy_content = f.read()

    expected_directive = f"proxy_pass http://unix:{bind_path};"
    assert expected_directive in proxy_content, (
        f"Expected '{expected_directive}' in {PROXY_CONF}, but it was not found."
    )


def test_update_config_script_is_dynamic_and_executable_as_a_script():
    with open(SERVER_CONF, "r") as f:
        original_server = f.read()
    with open(PROXY_CONF, "r") as f:
        original_proxy = f.read()

    original_bind = read_bind_path()
    assert original_bind is not None
    dynamic_path = f"/tmp/config-test-{uuid.uuid4().hex}.sock"
    decoy_path = f"/tmp/old-{uuid.uuid4().hex}.sock"

    changed_server = original_server.replace(
        f"BIND_PATH={original_bind}", f"BIND_PATH={dynamic_path}", 1
    )
    lines = original_proxy.splitlines(keepends=True)
    replaced = False
    for i, line in enumerate(lines):
        if "proxy_pass" in line and "http://unix:" in line:
            indent = line[: len(line) - len(line.lstrip())]
            ending = "\n" if line.endswith("\n") else ""
            lines[i] = f"{indent}proxy_pass http://unix:{decoy_path};{ending}"
            replaced = True
            break
    assert replaced, "No Unix proxy_pass directive found in proxy.conf"

    try:
        with open(SERVER_CONF, "w") as f:
            f.write(changed_server)
        with open(PROXY_CONF, "w") as f:
            f.write("".join(lines))

        result = subprocess.run(
            ["/bin/bash", SCRIPT_PATH], capture_output=True, text=True, timeout=10
        )
        assert result.returncode == 0, (
            f"update_config.sh failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        with open(PROXY_CONF, "r") as f:
            updated = f.read()
        assert f"proxy_pass http://unix:{dynamic_path};" in updated
        assert decoy_path not in updated
    finally:
        with open(SERVER_CONF, "w") as f:
            f.write(original_server)
        with open(PROXY_CONF, "w") as f:
            f.write(original_proxy)


def test_hcheck_executable_exists():
    assert os.path.isfile(HCHECK_PATH), f"Executable {HCHECK_PATH} does not exist."

    st = os.stat(HCHECK_PATH)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), (
        f"{HCHECK_PATH} is not executable."
    )

    with open(HCHECK_PATH, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"{HCHECK_PATH} is not a valid ELF executable."


def test_health_report_log():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."
    with open(LOG_PATH, "r") as f:
        content = f.read().strip()
    assert content == "HEALTHY", f"Expected 'HEALTHY' in {LOG_PATH}, got '{content}'."


def run_socket_case(executable, response):
    temp_dir = tempfile.mkdtemp(prefix="hcheck-test-", dir="/tmp")
    socket_path = os.path.join(temp_dir, "backend.sock")
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    listener.bind(socket_path)
    listener.listen(1)
    listener.settimeout(4)
    received = []
    errors = []

    def serve():
        try:
            conn, _ = listener.accept()
            with conn:
                conn.settimeout(1)
                data = b""
                while len(data) < 7:
                    chunk = conn.recv(4096)
                    if not chunk:
                        break
                    data += chunk

                # Wait briefly before replying so any bytes beyond STATUS\n are observed.
                conn.settimeout(0.15)
                try:
                    while True:
                        chunk = conn.recv(4096)
                        if not chunk:
                            break
                        data += chunk
                except socket.timeout:
                    pass
                received.append(data)
                conn.sendall(response)
        except Exception as exc:
            errors.append(exc)

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    try:
        result = subprocess.run(
            [executable, socket_path], capture_output=True, timeout=5
        )
    finally:
        thread.join(timeout=5)
        listener.close()
        try:
            os.unlink(socket_path)
        except FileNotFoundError:
            pass
        os.rmdir(temp_dir)

    assert not thread.is_alive(), "Health checker/server interaction timed out"
    assert not errors, f"Test socket server failed: {errors!r}"
    assert received == [b"STATUS\n"], (
        f"Health checker sent {received!r}; expected exactly b'STATUS\\n'"
    )
    return result


@pytest.fixture(scope="module")
def checker_executables():
    assert os.path.isfile(SOURCE_PATH), f"Source file {SOURCE_PATH} does not exist."
    build_dir = tempfile.mkdtemp(prefix="hcheck-build-", dir="/tmp")
    rebuilt = os.path.join(build_dir, "hcheck_rebuilt")
    result = subprocess.run(
        ["g++", "-std=c++17", "-o", rebuilt, SOURCE_PATH],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"health_check.cpp did not compile: stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    yield [HCHECK_PATH, rebuilt]
    try:
        os.unlink(rebuilt)
        os.rmdir(build_dir)
    except FileNotFoundError:
        pass


def test_health_checker_argument_handling(checker_executables):
    for executable in checker_executables:
        no_args = subprocess.run([executable], capture_output=True, timeout=5)
        assert no_args.returncode != 0, f"{executable} accepted zero arguments"

        extra_args = subprocess.run(
            [executable, "/tmp/does-not-exist.sock", "extra"],
            capture_output=True,
            timeout=5,
        )
        assert extra_args.returncode != 0, f"{executable} accepted more than one argument"


def test_health_checker_success_and_exact_request(checker_executables):
    for executable in checker_executables:
        try:
            os.unlink(LOG_PATH)
        except FileNotFoundError:
            pass

        result = run_socket_case(executable, b"backend status: OK\n")
        assert result.returncode == 0, (
            f"{executable} returned {result.returncode} for an OK response; "
            f"stderr={result.stderr!r}"
        )
        assert os.path.isfile(LOG_PATH), f"{executable} did not create {LOG_PATH}"
        with open(LOG_PATH, "rb") as f:
            assert f.read() == b"HEALTHY", (
                f"{executable} did not write the exact bytes b'HEALTHY'"
            )


def test_health_checker_rejects_non_ok_response(checker_executables):
    for executable in checker_executables:
        result = run_socket_case(executable, b"backend unavailable\n")
        assert result.returncode != 0, (
            f"{executable} returned success for a response without 'OK'"
        )


def test_health_checker_connect_failure(checker_executables):
    for executable in checker_executables:
        missing = f"/tmp/missing-{uuid.uuid4().hex}.sock"
        result = subprocess.run([executable, missing], capture_output=True, timeout=5)
        assert result.returncode != 0, (
            f"{executable} returned success when connection failed"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
