#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/check_diag_ast.go
package main

import (
    "fmt"
    "go/ast"
    "go/importer"
    "go/parser"
    "go/token"
    "go/types"
    "os"
)

func main() {
    path := os.Args[len(os.Args)-1]
    fset := token.NewFileSet()
    file, err := parser.ParseFile(fset, path, nil, 0)
    if err != nil {
        panic(err)
    }

    info := &types.Info{
        Uses: make(map[*ast.Ident]types.Object),
    }
    conf := types.Config{Importer: importer.Default()}
    if _, err := conf.Check("network_diag", fset, []*ast.File{file}, info); err != nil {
        panic(err)
    }

    found := false
    ast.Inspect(file, func(n ast.Node) bool {
        call, ok := n.(*ast.CallExpr)
        if !ok || len(call.Args) != 3 {
            return true
        }
        sel, ok := call.Fun.(*ast.SelectorExpr)
        if !ok {
            return true
        }
        obj, ok := info.Uses[sel.Sel].(*types.Func)
        if ok && obj.Name() == "DialTimeout" && obj.Pkg() != nil && obj.Pkg().Path() == "net" {
            found = true
        }
        return true
    })

    if !found {
        fmt.Fprintln(os.Stderr, "diag.go does not call net.DialTimeout with three arguments")
        os.Exit(1)
    }
}
GO_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import socket
import stat
import subprocess
import threading
import time

import pytest

DIAG_DIR = "/home/user/network_diag"
SETUP_SCRIPT = os.path.join(DIAG_DIR, "setup.sh")
ROLES_JSON = os.path.join(DIAG_DIR, "roles.json")
DIAG_GO = os.path.join(DIAG_DIR, "diag.go")
DIAG_TOOL = os.path.join(DIAG_DIR, "diag_tool")
SOURCE_TOOL = "/tmp/diag_tool_from_source"
AUDIT_LOG = os.path.join(DIAG_DIR, "audit.log")
EXPECTED_ROLES = {
    "netadmin": ["127.0.0.1:9001", "127.0.0.1:9002", "127.0.0.1:9003"],
    "appdev": ["127.0.0.1:9001"],
    "guest": ["127.0.0.1:9003"],
}


@pytest.fixture(scope="session", autouse=True)
def run_setup_and_build_source():
    assert os.path.isfile(SETUP_SCRIPT), f"{SETUP_SCRIPT} does not exist."
    st = os.stat(SETUP_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"{SETUP_SCRIPT} is not executable."

    result = subprocess.run(
        [SETUP_SCRIPT], cwd=DIAG_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, (
        f"setup.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.isfile(DIAG_GO), f"{DIAG_GO} does not exist."
    ast_check = subprocess.run(
        ["go", "run", "/tmp/check_diag_ast.go", "--", DIAG_GO],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert ast_check.returncode == 0, ast_check.stderr

    build = subprocess.run(
        ["go", "build", "-o", SOURCE_TOOL, DIAG_GO],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert build.returncode == 0, f"diag.go did not compile:\n{build.stderr}"
    yield


def test_setup_script_exists_and_executable():
    assert os.path.isfile(SETUP_SCRIPT), f"{SETUP_SCRIPT} does not exist."
    st = os.stat(SETUP_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"{SETUP_SCRIPT} is not executable."


def test_diag_go_exists_and_is_go_source():
    assert os.path.isfile(DIAG_GO), f"{DIAG_GO} does not exist."
    assert os.path.isfile(SOURCE_TOOL) and os.access(SOURCE_TOOL, os.X_OK)


def test_roles_json_content():
    assert os.path.isfile(ROLES_JSON), f"{ROLES_JSON} does not exist."
    with open(ROLES_JSON, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{ROLES_JSON} is not valid JSON.")
    assert data == EXPECTED_ROLES, (
        f"Contents of {ROLES_JSON} do not match the expected configuration."
    )


def test_diag_tool_exists_and_executable():
    assert os.path.isfile(DIAG_TOOL), f"{DIAG_TOOL} does not exist. Did setup.sh compile it?"
    st = os.stat(DIAG_TOOL)
    assert bool(st.st_mode & stat.S_IXUSR), f"{DIAG_TOOL} is not executable."
    version = subprocess.run(
        ["go", "version", "-m", DIAG_TOOL], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert version.returncode == 0 and "go1." in version.stdout, (
        f"{DIAG_TOOL} is not a Go executable built by setup.sh."
    )


def wait_for_port(port, timeout=5):
    start = time.time()
    while time.time() - start < timeout:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            if s.connect_ex(("127.0.0.1", port)) == 0:
                return True
        time.sleep(0.1)
    return False


def run_tool(tool, username, timeout=5):
    process = subprocess.Popen(
        [tool], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True
    )
    stdout, stderr = process.communicate(input=username + "\n", timeout=timeout)
    return process.returncode, stdout, stderr


def test_diag_tool_invalid_user():
    returncode, stdout, stderr = run_tool(DIAG_TOOL, "hacker", timeout=2)
    assert returncode == 1, f"Expected exit code 1 for invalid user, got {returncode}."
    assert "Access Denied" in stdout or "Access Denied" in stderr, (
        "Expected 'Access Denied' output for invalid user."
    )
    assert stdout.startswith("Enter username: "), "The required prompt was not printed exactly."
    assert "Access Denied" in stdout, "Access Denied must be printed to standard output."


def test_diag_tool_valid_user_and_audit_log():
    p1 = subprocess.Popen(
        ["python3", "-m", "http.server", "9001"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    p2 = subprocess.Popen(
        ["python3", "-m", "http.server", "9002"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )

    try:
        assert wait_for_port(9001), "Failed to start listener on port 9001 for testing."
        assert wait_for_port(9002), "Failed to start listener on port 9002 for testing."
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            assert s.connect_ex(("127.0.0.1", 9003)) != 0, (
                "Port 9003 should be closed for this test."
            )

        if os.path.exists(AUDIT_LOG):
            os.remove(AUDIT_LOG)

        returncode, stdout, stderr = run_tool(DIAG_TOOL, "netadmin")
        assert returncode == 0, f"Expected exit code 0 for valid user, got {returncode}."
        assert stdout.startswith("Enter username: "), "The required prompt was not printed exactly."
        assert os.path.isfile(AUDIT_LOG), f"{AUDIT_LOG} was not created."

        with open(AUDIT_LOG, "r") as f:
            log_contents = f.read()

        expected_lines = [
            "[netadmin] checked 127.0.0.1:9001: OK",
            "[netadmin] checked 127.0.0.1:9002: OK",
            "[netadmin] checked 127.0.0.1:9003: FAIL",
        ]
        for line in expected_lines:
            assert line in log_contents, (
                f"Expected line '{line}' not found in {AUDIT_LOG}. "
                f"Log contents:\n{log_contents}"
            )
    finally:
        p1.terminate()
        p2.terminate()
        p1.wait()
        p2.wait()


def test_source_binary_loads_runtime_rbac_and_checks_dynamic_endpoints():
    with open(ROLES_JSON, "rb") as f:
        original_roles = f.read()

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(8)
    listener.settimeout(0.2)
    open_port = listener.getsockname()[1]

    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.bind(("127.0.0.1", 0))
    closed_port = probe.getsockname()[1]
    probe.close()

    stop = threading.Event()

    def accept_connections():
        while not stop.is_set():
            try:
                conn, _ = listener.accept()
                conn.close()
            except socket.timeout:
                pass
            except OSError:
                break

    thread = threading.Thread(target=accept_connections, daemon=True)
    thread.start()

    username = "user_" + secrets.token_hex(8)
    invalid_username = "missing_" + secrets.token_hex(8)
    open_endpoint = f"127.0.0.1:{open_port}"
    closed_endpoint = f"127.0.0.1:{closed_port}"
    dynamic_roles = {username: [open_endpoint, closed_endpoint]}

    try:
        with open(ROLES_JSON, "w") as f:
            json.dump(dynamic_roles, f)
        if os.path.exists(AUDIT_LOG):
            os.remove(AUDIT_LOG)

        returncode, stdout, stderr = run_tool(SOURCE_TOOL, invalid_username)
        assert returncode == 1
        assert stdout.startswith("Enter username: ")
        assert "Access Denied" in stdout
        assert not os.path.exists(AUDIT_LOG), "Invalid users must not create audit results."

        returncode, stdout, stderr = run_tool(SOURCE_TOOL, username)
        assert returncode == 0, f"Dynamic valid user failed: {stderr}"
        assert stdout.startswith("Enter username: ")
        assert os.path.isfile(AUDIT_LOG)
        with open(AUDIT_LOG, "r") as f:
            lines = f.read().splitlines()

        assert lines == [
            f"[{username}] checked {open_endpoint}: OK",
            f"[{username}] checked {closed_endpoint}: FAIL",
        ], f"Unexpected dynamic audit output: {lines!r}"
    finally:
        stop.set()
        listener.close()
        thread.join(timeout=1)
        with open(ROLES_JSON, "wb") as f:
            f.write(original_roles)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
