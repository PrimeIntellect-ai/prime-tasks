#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import socket
import socketserver
import stat
import subprocess
import tempfile
import threading
import time

import pytest

BASE_DIR = "/home/user/ci-runner"
PIPELINE = os.path.join(BASE_DIR, "pipeline.sh")
RUNNER = os.path.join(BASE_DIR, "bin", "runner")
MAIN_GO = os.path.join(BASE_DIR, "main.go")


def port_is_open(port):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.25):
            return True
    except OSError:
        return False


def wait_for_port_closed(port, timeout=3):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not port_is_open(port):
            time.sleep(0.15)
            if not port_is_open(port):
                return True
        time.sleep(0.1)
    return False


def run_pipeline():
    return subprocess.run(
        [PIPELINE], cwd=BASE_DIR, capture_output=True, text=True, timeout=30
    )


@pytest.fixture(scope="session", autouse=True)
def verify_pipeline_builds_and_runs_main():
    assert os.path.isfile(MAIN_GO), "main.go does not exist"
    assert os.path.isfile(PIPELINE), "pipeline.sh does not exist"
    assert os.stat(PIPELINE).st_mode & stat.S_IXUSR, "pipeline.sh is not executable"
    assert not port_is_open(8080), "TCP port 8080 was already occupied before pipeline.sh ran"

    with open(MAIN_GO, "rb") as f:
        original_main = f.read()
    original_mode = stat.S_IMODE(os.stat(MAIN_GO).st_mode)

    marker = os.path.join(tempfile.gettempdir(), "pipeline-probe-" + secrets.token_hex(12))
    probe_source = '''package main

import (
    "fmt"
    "net"
    "os"
    "strings"
    "time"
)

func main() {
    if len(os.Args) != 4 {
        os.Exit(90)
    }
    conn, err := net.DialTimeout("tcp", os.Args[3], 3*time.Second)
    if err != nil {
        os.Exit(91)
    }
    conn.Close()
    if err := os.WriteFile(MARKER_PATH, []byte(strings.Join(os.Args[1:], "\\n")), 0600); err != nil {
        os.Exit(92)
    }
    fmt.Println("ACCESS_GRANTED")
}
'''.replace("MARKER_PATH", json.dumps(marker))

    try:
        with open(MAIN_GO, "w") as f:
            f.write(probe_source)
        os.chmod(MAIN_GO, original_mode)
        for path in (RUNNER, os.path.join(BASE_DIR, "test.log"), marker):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        result = run_pipeline()
        assert result.returncode == 0, (
            f"pipeline.sh failed while tested with an instrumented main.go: "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert os.path.isfile(RUNNER), "pipeline.sh did not create bin/runner"
        assert os.access(RUNNER, os.X_OK), "pipeline.sh did not create an executable runner"
        assert os.path.isfile(marker), (
            "pipeline.sh did not compile main.go and execute the resulting runner"
        )
        with open(marker) as f:
            invoked_args = f.read()
        assert invoked_args == "bob\nrestart\nlocalhost:8080", (
            f"pipeline.sh invoked the runner with incorrect arguments: {invoked_args!r}"
        )
        with open(os.path.join(BASE_DIR, "test.log")) as f:
            assert f.read().strip() == "ACCESS_GRANTED"
        assert wait_for_port_closed(8080), "pipeline.sh left its TCP listener running"
    finally:
        with open(MAIN_GO, "wb") as f:
            f.write(original_main)
        os.chmod(MAIN_GO, original_mode)
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass

    for path in (RUNNER, os.path.join(BASE_DIR, "test.log")):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = run_pipeline()
    assert result.returncode == 0, (
        f"pipeline.sh failed with the submitted main.go: "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(RUNNER) and os.access(RUNNER, os.X_OK)
    assert os.path.isfile(os.path.join(BASE_DIR, "test.log"))
    assert wait_for_port_closed(8080), "pipeline.sh left its TCP listener running"
    yield


def test_files_exist():
    required_files = [
        "roles.conf",
        "main.go",
        "pipeline.sh",
        "bin/runner",
        "test.log",
    ]
    for filename in required_files:
        path = os.path.join(BASE_DIR, filename)
        assert os.path.exists(path), f"Required file {path} does not exist."


def test_roles_conf_content():
    roles_path = os.path.join(BASE_DIR, "roles.conf")
    with open(roles_path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "alice:dev:deploy,status",
        "bob:admin:deploy,status,restart",
        "charlie:qa:status",
    ]
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert actual_lines == expected_lines, "roles.conf does not contain the exact expected mappings."


def test_pipeline_sh_executable():
    st = os.stat(PIPELINE)
    assert bool(st.st_mode & stat.S_IXUSR), f"{PIPELINE} is not executable."


def test_test_log_content():
    with open(os.path.join(BASE_DIR, "test.log"), "r") as f:
        content = f.read().strip()
    assert content == "ACCESS_GRANTED", f"test.log content is {content!r}, expected 'ACCESS_GRANTED'."


def test_runner_is_go_program_buildable_from_main():
    with open(RUNNER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "bin/runner is not a compiled ELF executable"
    metadata = subprocess.run(["go", "version", "-m", RUNNER], capture_output=True, text=True)
    assert metadata.returncode == 0, "bin/runner is not recognized as a Go executable"

    fresh = os.path.join(tempfile.gettempdir(), "runner-from-main-" + secrets.token_hex(10))
    try:
        built = subprocess.run(
            ["go", "build", "-o", fresh, MAIN_GO],
            cwd=BASE_DIR, capture_output=True, text=True, timeout=30
        )
        assert built.returncode == 0, f"main.go does not compile: {built.stderr}"
        result = subprocess.run([fresh], capture_output=True, text=True, timeout=5)
        assert result.returncode != 0, "freshly compiled main.go accepts zero positional arguments"
    finally:
        try:
            os.remove(fresh)
        except FileNotFoundError:
            pass


def get_free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class ConnectionHandler(socketserver.BaseRequestHandler):
    def handle(self):
        return


class TestServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def invoke(args):
    return subprocess.run([RUNNER] + args, capture_output=True, text=True, timeout=8)


def assert_result(result, code, output):
    assert result.returncode == code, (
        f"Expected exit code {code}, got {result.returncode}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert output in result.stdout, f"Expected {output!r} in stdout, got {result.stdout!r}"


def test_runner_binary_behavior():
    port = get_free_port()
    server = TestServer(("127.0.0.1", port), ConnectionHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    endpoint = f"localhost:{port}"

    try:
        # Preserve the original fixed reachable checks.
        assert_result(invoke(["charlie", "deploy", endpoint]), 3, "ACCESS_DENIED")
        assert_result(invoke(["alice", "deploy", endpoint]), 0, "ACCESS_GRANTED")

        # Exercise every authorization listed in roles.conf.
        authorized = {
            "alice": ("deploy", "status"),
            "bob": ("deploy", "status", "restart"),
            "charlie": ("status",),
        }
        for user, commands in authorized.items():
            for command in commands:
                assert_result(invoke([user, command, endpoint]), 0, "ACCESS_GRANTED")

        # Runtime-random values prevent a fixed table of verifier cases from passing.
        random_command = "cmd_" + secrets.token_hex(16)
        random_user = "user_" + secrets.token_hex(16)
        denied = [
            ("alice", "restart"),
            ("charlie", "deploy"),
            ("charlie", "restart"),
            ("alice", random_command),
            ("bob", random_command),
            (random_user, "deploy"),
            (random_user, random_command),
        ]
        for user, command in denied:
            assert_result(invoke([user, command, endpoint]), 3, "ACCESS_DENIED")

        # Exactly three positional arguments must be required.
        bad_arg_lists = [
            [],
            ["bob"],
            ["bob", "restart"],
            ["bob", "restart", endpoint, "extra"],
        ]
        for args in bad_arg_lists:
            result = invoke(args)
            assert result.returncode != 0, f"Runner accepted invalid argument list {args!r}"
            assert "ACCESS_GRANTED" not in result.stdout
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    # Preserve the original unreachable check and verify connectivity is checked
    # before authorization for authorized, unauthorized, and unknown identities.
    bad_port = get_free_port()
    unreachable = f"localhost:{bad_port}"
    assert_result(invoke(["bob", "deploy", unreachable]), 2, "ENDPOINT_UNREACHABLE")
    assert_result(invoke(["charlie", "deploy", unreachable]), 2, "ENDPOINT_UNREACHABLE")
    assert_result(
        invoke(["unknown_" + secrets.token_hex(12), "unknown_" + secrets.token_hex(12), unreachable]),
        2,
        "ENDPOINT_UNREACHABLE",
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
