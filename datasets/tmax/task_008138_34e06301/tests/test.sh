#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import socket
import stat
import subprocess
import tempfile
import uuid

RUN_SCRIPT = "/home/user/netmon/run.sh"
GO_FILE = "/home/user/netmon/monitor.go"
LOG_DIR = "/home/user/net_logs"
LOG_FILE = "/home/user/net_logs/status.log"


def run(cmd, env=None):
    return subprocess.run(cmd, env=env, capture_output=True, text=True)


def test_files_exist_and_go_script_reads_env_var():
    assert os.path.isfile(RUN_SCRIPT), f"{RUN_SCRIPT} is missing"
    assert os.path.isfile(GO_FILE), f"{GO_FILE} is missing"
    with open(GO_FILE, "r") as f:
        content = f.read()
    assert "NET_LOG_DIR" in content, "monitor.go does not appear to read the NET_LOG_DIR environment variable"


def test_go_program_environment_path_and_real_port_detection():
    """Compile and execute monitor.go itself against derived open/closed port states."""
    with tempfile.TemporaryDirectory(prefix="netmon-test-") as td:
        binary = os.path.join(td, "monitor")
        cache = os.path.join(td, "gocache")
        os.mkdir(cache)
        build_env = {
            "PATH": "/usr/local/go/bin:/usr/bin:/bin",
            "HOME": "/home/user",
            "GOCACHE": cache,
        }
        result = run(["/usr/bin/go", "build", "-o", binary, GO_FILE], env=build_env)
        assert result.returncode == 0, f"monitor.go does not build: {result.stderr}"

        custom_dir = os.path.join(td, "logs")
        os.mkdir(custom_dir)
        custom_log = os.path.join(custom_dir, "status.log")

        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            listener.bind(("127.0.0.1", 8080))
            listener.listen(1)
        except OSError as exc:
            listener.close()
            raise AssertionError(f"Port 8080 must be free for the monitor test: {exc}")

        try:
            result = run([binary], env={"NET_LOG_DIR": custom_dir})
            assert result.returncode == 0, f"compiled monitor failed: {result.stderr}"
            assert os.path.isfile(custom_log), "monitor.go did not write status.log under NET_LOG_DIR"
            with open(custom_log, "r") as f:
                assert f.read() == "STATUS: 8080_OPEN\n", "monitor.go did not detect a listening port 8080"
        finally:
            listener.close()

        fallback = "/tmp/status.log"
        try:
            os.unlink(fallback)
        except FileNotFoundError:
            pass
        result = run([binary], env={})
        assert result.returncode == 0, f"compiled monitor failed with NET_LOG_DIR unset: {result.stderr}"
        assert os.path.isfile(fallback), "monitor.go did not fall back to /tmp/status.log"
        with open(fallback, "r") as f:
            assert f.read() == "STATUS: 8080_CLOSED\n", "monitor.go did not detect closed port 8080"


def test_run_sh_execution_in_empty_env_and_original_output_checks():
    """Keep the original wrapper, permission, and output assertions."""
    shutil.rmtree(LOG_DIR, ignore_errors=True)
    result = run(["env", "-i", "bash", RUN_SCRIPT])
    assert result.returncode == 0, f"run.sh failed to execute in an empty environment. stderr: {result.stderr}"

    assert os.path.isdir(LOG_DIR), f"Directory {LOG_DIR} is missing"
    perms = stat.S_IMODE(os.stat(LOG_DIR).st_mode)
    assert perms == 0o750, f"Directory {LOG_DIR} permissions are {oct(perms)}, expected 0o750"

    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} is missing"
    with open(LOG_FILE, "r") as f:
        content = f.read()
    assert "STATUS: 8080_CLOSED" in content, f"Incorrect or missing content in {LOG_FILE}. Found: {content}"


def test_wrapper_really_executes_go_source_with_required_environment():
    """Replace monitor.go temporarily with a probe so shell-fabricated output cannot pass."""
    with open(GO_FILE, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(GO_FILE).st_mode)
    nonce = uuid.uuid4().hex
    probe = r'''package main

import (
    "fmt"
    "os"
    "path/filepath"
)

func main() {
    dir := os.Getenv("NET_LOG_DIR")
    f, err := os.Create(filepath.Join(dir, "status.log"))
    if err != nil {
        panic(err)
    }
    defer f.Close()
    fmt.Fprintf(f, "%s\nNET_LOG_DIR=%s\nHOME=%s\nGOCACHE=%s\nPATH=%s\n",
        "__NONCE__", dir, os.Getenv("HOME"), os.Getenv("GOCACHE"), os.Getenv("PATH"))
}
'''.replace("__NONCE__", nonce)

    try:
        with open(GO_FILE, "w") as f:
            f.write(probe)
        shutil.rmtree(LOG_DIR, ignore_errors=True)
        result = run(["env", "-i", "bash", RUN_SCRIPT])
        assert result.returncode == 0, f"run.sh did not execute the Go probe: {result.stderr}"
        assert os.path.isfile(LOG_FILE), "the Go probe did not create the log file"
        with open(LOG_FILE, "r") as f:
            lines = f.read().splitlines()
        assert lines and lines[0] == nonce, "run.sh did not actually execute monitor.go"

        values = {}
        for line in lines[1:]:
            if "=" in line:
                key, value = line.split("=", 1)
                values[key] = value
        assert values.get("NET_LOG_DIR") == LOG_DIR, "run.sh did not export NET_LOG_DIR correctly"
        assert values.get("HOME") == "/home/user" or values.get("GOCACHE") == "/home/user/.cache/go-build", \
            "run.sh did not provide the required HOME or GOCACHE"

        path_value = values.get("PATH", "")
        path_entries = path_value.split(":")
        assert any(p in ("/bin", "/usr/bin") for p in path_entries), "PATH lacks standard system binaries"
        assert any(os.path.isfile(os.path.join(p, "go")) and os.access(os.path.join(p, "go"), os.X_OK)
                   for p in path_entries if p), "PATH does not contain an executable Go binary"

        perms = stat.S_IMODE(os.stat(LOG_DIR).st_mode)
        assert perms == 0o750, f"Directory {LOG_DIR} permissions are {oct(perms)}, expected 0o750"
    finally:
        with open(GO_FILE, "wb") as f:
            f.write(original)
        os.chmod(GO_FILE, original_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
