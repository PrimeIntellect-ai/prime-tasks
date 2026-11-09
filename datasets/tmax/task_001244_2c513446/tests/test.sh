#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import socket
import subprocess
import time
import uuid

import pytest

ORCH_DIR = "/home/user/go_orchestrator"
RUST_DIR = "/home/user/rust_target"
REPORT_FILE = "/home/user/e2e_report.json"


def stop_listener_on_8080():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].endswith(":1F90") and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except OSError:
            pass

    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if pids:
        time.sleep(0.5)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_server(proc):
    deadline = time.time() + 15
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail("The submitted Go server exited before accepting connections.")
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail("The submitted Go server did not listen on port 8080.")


@pytest.fixture(scope="session", autouse=True)
def run_real_orchestration(tmp_path_factory):
    server_bin = "/tmp/verifier_orchestrator_server"
    probe_src = os.path.join(ORCH_DIR, "verifier_probe_tmp.go")
    probe_bin = "/tmp/verifier_ws_probe"

    build_server = subprocess.run(
        ["go", "build", "-o", server_bin, "server.go"],
        cwd=ORCH_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert build_server.returncode == 0, (
        "server.go did not build:\n" + build_server.stdout + build_server.stderr
    )

    marker = "orchestration-marker-" + uuid.uuid4().hex
    dynamic_project = tmp_path_factory.mktemp("server-command-target")
    (dynamic_project / "src").mkdir()
    (dynamic_project / "Cargo.toml").write_text(
        '[package]\nname = "verifier_target"\nversion = "0.1.0"\nedition = "2021"\n'
    )
    (dynamic_project / "src" / "main.rs").write_text(
        'fn main() { println!("' + marker + '"); }\n'
    )

    probe_code = r'''package main

import (
    "encoding/json"
    "fmt"
    "os"
    "strings"
    "time"

    "github.com/gorilla/websocket"
)

type Response struct {
    Command string `json:"command"`
    Success bool   `json:"success"`
    Output  string `json:"output"`
}

func exchange(c *websocket.Conn, command string) Response {
    if err := c.WriteMessage(websocket.TextMessage, []byte(command)); err != nil {
        panic(err)
    }
    _, data, err := c.ReadMessage()
    if err != nil {
        panic(err)
    }
    var response Response
    if err := json.Unmarshal(data, &response); err != nil {
        panic(err)
    }
    if response.Command != command {
        panic(fmt.Sprintf("wrong echoed command: %q", response.Command))
    }
    if !response.Success {
        panic(fmt.Sprintf("command failed: %s", response.Output))
    }
    return response
}

func main() {
    if len(os.Args) != 3 {
        panic("expected project path and marker")
    }
    c, _, err := websocket.DefaultDialer.Dial("ws://127.0.0.1:8080/ws", nil)
    if err != nil {
        panic(err)
    }
    defer c.Close()
    c.SetDeadline(time.Now().Add(60 * time.Second))

    exchange(c, "BUILD "+os.Args[1])
    run := exchange(c, "RUN "+os.Args[1])
    if !strings.Contains(run.Output, os.Args[2]) {
        panic(fmt.Sprintf("RUN output did not contain dynamic marker: %q", run.Output))
    }
}
'''
    with open(probe_src, "w") as f:
        f.write(probe_code)
    try:
        build_probe = subprocess.run(
            ["go", "build", "-o", probe_bin, probe_src],
            cwd=ORCH_DIR,
            capture_output=True,
            text=True,
            timeout=60,
        )
    finally:
        try:
            os.remove(probe_src)
        except FileNotFoundError:
            pass
    assert build_probe.returncode == 0, (
        "Could not build verifier WebSocket client:\n"
        + build_probe.stdout
        + build_probe.stderr
    )

    stop_listener_on_8080()
    log_file = open("/tmp/verifier_server.log", "w+")
    server = subprocess.Popen(
        [server_bin],
        cwd=ORCH_DIR,
        stdout=log_file,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    try:
        wait_for_server(server)

        probe = subprocess.run(
            [probe_bin, str(dynamic_project), marker],
            capture_output=True,
            text=True,
            timeout=90,
        )
        assert probe.returncode == 0, (
            "The live server failed WebSocket BUILD/RUN commands against a dynamic "
            "Rust project:\n" + probe.stdout + probe.stderr
        )

        try:
            os.remove(REPORT_FILE)
        except FileNotFoundError:
            pass
        client = subprocess.run(
            [
                "go",
                "run",
                "client.go",
                "-script",
                "/home/user/test_script.txt",
                "-output",
                REPORT_FILE,
            ],
            cwd=ORCH_DIR,
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert client.returncode == 0, (
            "The provided client failed while talking to the submitted server:\n"
            + client.stdout
            + client.stderr
        )
        assert os.path.isfile(REPORT_FILE), "The real client did not generate e2e_report.json."
        yield
    finally:
        try:
            os.killpg(server.pid, signal.SIGTERM)
            server.wait(timeout=3)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                os.killpg(server.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        log_file.close()


def test_rust_project_fixed():
    """Verify that the Rust project compiles successfully."""
    rust_dir = "/home/user/rust_target"
    assert os.path.isdir(rust_dir), f"Directory {rust_dir} does not exist."

    result = subprocess.run(["cargo", "build"], cwd=rust_dir, capture_output=True, text=True)
    assert result.returncode == 0, f"Rust project failed to compile. Error:\n{result.stderr}"


def test_rust_project_runs_correctly():
    """Verify that the Rust project runs and prints the expected output."""
    rust_dir = "/home/user/rust_target"
    result = subprocess.run(["cargo", "run"], cwd=rust_dir, capture_output=True, text=True)
    assert result.returncode == 0, f"Rust project failed to run. Error:\n{result.stderr}"
    assert "Hello from the helper!" in result.stdout, "Rust project did not print the expected message."


def test_go_server_fixed():
    """Verify that the Go server no longer splits by pipe."""
    server_go = "/home/user/go_orchestrator/server.go"
    assert os.path.isfile(server_go), f"Missing {server_go}"

    with open(server_go, "r") as f:
        content = f.read()

    assert 'strings.Split(msg, "|")' not in content, "The bug in server.go (splitting by pipe) is still present."


def test_test_script_exists_and_correct():
    """Verify that the test script contains the correct commands."""
    test_script = "/home/user/test_script.txt"
    assert os.path.isfile(test_script), f"Missing {test_script}"

    with open(test_script, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {test_script}, found {len(lines)}"
    assert lines[0] == "BUILD /home/user/rust_target", f"First line in {test_script} is incorrect."
    assert lines[1] == "RUN /home/user/rust_target", f"Second line in {test_script} is incorrect."


def test_e2e_report_valid_and_successful():
    """Verify the freshly generated e2e JSON report contains successful results."""
    report_file = "/home/user/e2e_report.json"
    assert os.path.isfile(report_file), f"Missing {report_file}. Did you run the Go client?"

    with open(report_file, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{report_file} is not valid JSON.")

    assert isinstance(data, list), f"Expected JSON root to be a list, got {type(data).__name__}"
    assert len(data) == 2, f"Expected exactly 2 results in JSON, got {len(data)}"

    build_res = data[0]
    run_res = data[1]

    assert build_res.get("command") == "BUILD /home/user/rust_target", "First command in report is incorrect."
    assert build_res.get("success") is True, f"BUILD command failed. Output: {build_res.get('output')}"

    assert run_res.get("command") == "RUN /home/user/rust_target", "Second command in report is incorrect."
    assert run_res.get("success") is True, f"RUN command failed. Output: {run_res.get('output')}"
    assert "Hello from the helper!" in run_res.get("output", ""), "RUN command output missing expected message."
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
