#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import signal
import socket
import subprocess
import time
import uuid
from pathlib import Path

import pytest
import requests

SERVER_BINARY = "/tmp/patched-go-server"
UPLOAD_ROOT = Path("/app/server/uploads").resolve()
SERVER_PROCESS = None


def kill_port_8080_listeners():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[3] == "0A":
                try:
                    port = int(fields[1].rsplit(":", 1)[1], 16)
                except ValueError:
                    continue
                if port == 8080:
                    inodes.add(fields[9])

    if not inodes:
        return

    for proc_entry in Path("/proc").iterdir():
        if not proc_entry.name.isdigit():
            continue
        fd_dir = proc_entry / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    try:
                        os.kill(int(proc_entry.name), signal.SIGTERM)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except (OSError, PermissionError):
            continue
    time.sleep(0.5)


@pytest.fixture(scope="session", autouse=True)
def build_and_run_submitted_server():
    global SERVER_PROCESS
    source = Path("/app/server/main.go")
    assert source.is_file(), "/app/server/main.go is missing"

    build = subprocess.run(
        ["go", "build", "-o", SERVER_BINARY, str(source)],
        cwd="/app/server",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert build.returncode == 0, f"Patched Go source does not build:\n{build.stdout}"

    kill_port_8080_listeners()
    SERVER_PROCESS = subprocess.Popen(
        [SERVER_BINARY],
        cwd="/app/server",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    deadline = time.time() + 10
    while time.time() < deadline:
        if SERVER_PROCESS.poll() is not None:
            pytest.fail(f"Server built from /app/server/main.go exited with code {SERVER_PROCESS.returncode}")
        try:
            requests.get("http://localhost:8080/token", timeout=0.3)
            break
        except requests.RequestException:
            time.sleep(0.1)
    else:
        pytest.fail("Server built from /app/server/main.go did not start on localhost:8080")

    yield
    # Deliberately leave the verified server running, as required by the task.


def test_decrypted_evidence():
    decrypted_path = "/app/evidence/decrypted.txt"
    assert os.path.isfile(decrypted_path), f"Decrypted evidence file not found at {decrypted_path}"

    with open(decrypted_path, "r") as f:
        content = f.read().strip()

    expected_token = "AUTH_TOKEN: 8f9b2a1c-7e6d-4f5a-9b2c-1d9e8f7a6b5c"
    assert content == expected_token, f"Decrypted text does not match the expected token. Got: {content}"


def test_server_token_endpoint():
    url = "http://localhost:8080/token"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the Go server at {url}. Is it running? Error: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 from /token, got {response.status_code}"

    expected_token = "AUTH_TOKEN: 8f9b2a1c-7e6d-4f5a-9b2c-1d9e8f7a6b5c"
    assert response.text.strip() == expected_token, f"Expected response body to be '{expected_token}', got '{response.text}'"


def test_main_go_contains_effective_filename_sanitization():
    analyzer = r'''
package main

import (
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "path/filepath"
)

func selectorName(e ast.Expr) string {
    if s, ok := e.(*ast.SelectorExpr); ok {
        return s.Sel.Name
    }
    return ""
}

func isHandlerFilename(e ast.Expr) bool {
    s, ok := e.(*ast.SelectorExpr)
    if !ok || s.Sel.Name != "Filename" {
        return false
    }
    id, ok := s.X.(*ast.Ident)
    return ok && id.Name == "handler"
}

func main() {
    if len(os.Args) != 2 {
        os.Exit(2)
    }
    fset := token.NewFileSet()
    f, err := parser.ParseFile(fset, os.Args[1], nil, 0)
    if err != nil {
        os.Exit(3)
    }

    var body *ast.BlockStmt
    for _, d := range f.Decls {
        if fn, ok := d.(*ast.FuncDecl); ok && fn.Name.Name == "uploadHandler" {
            body = fn.Body
        }
    }
    if body == nil {
        os.Exit(4)
    }

    safeNames := map[string]bool{}
    safePaths := map[string]bool{}
    roots := map[string]bool{}

    var isRoot func(ast.Expr) bool
    var isSafeName func(ast.Expr) bool
    var isSafePath func(ast.Expr) bool

    isRoot = func(e ast.Expr) bool {
        switch x := e.(type) {
        case *ast.BasicLit:
            if x.Kind != token.STRING {
                return false
            }
            value, err := strconvUnquote(x.Value)
            return err == nil && filepath.Clean(value) == "/app/server/uploads"
        case *ast.Ident:
            return roots[x.Name]
        }
        return false
    }

    isSafeName = func(e ast.Expr) bool {
        switch x := e.(type) {
        case *ast.Ident:
            return safeNames[x.Name]
        case *ast.CallExpr:
            return selectorName(x.Fun) == "Base" && len(x.Args) == 1 && isHandlerFilename(x.Args[0])
        }
        return false
    }

    isSafePath = func(e ast.Expr) bool {
        switch x := e.(type) {
        case *ast.Ident:
            return safePaths[x.Name]
        case *ast.CallExpr:
            return selectorName(x.Fun) == "Join" && len(x.Args) >= 2 && isRoot(x.Args[0]) && isSafeName(x.Args[len(x.Args)-1])
        }
        return false
    }

    sinks := 0
    unsafeSink := false
    ast.Inspect(body, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.AssignStmt:
            for i, lhs := range x.Lhs {
                if i >= len(x.Rhs) {
                    continue
                }
                id, ok := lhs.(*ast.Ident)
                if !ok {
                    continue
                }
                rhs := x.Rhs[i]
                if isRoot(rhs) {
                    roots[id.Name] = true
                }
                if isSafeName(rhs) {
                    safeNames[id.Name] = true
                }
                if isSafePath(rhs) {
                    safePaths[id.Name] = true
                }
            }
        case *ast.CallExpr:
            name := selectorName(x.Fun)
            if (name == "Create" || name == "OpenFile") && len(x.Args) > 0 {
                sinks++
                if !isSafePath(x.Args[0]) {
                    unsafeSink = true
                }
            }
        }
        return true
    })

    if sinks == 0 || unsafeSink {
        os.Exit(5)
    }
}

func strconvUnquote(s string) (string, error) {
    if len(s) < 2 {
        return "", os.ErrInvalid
    }
    return s[1:len(s)-1], nil
}
'''
    analyzer_path = "/tmp/check_upload_patch.go"
    Path(analyzer_path).write_text(analyzer)
    result = subprocess.run(
        ["go", "run", analyzer_path, "/app/server/main.go"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, (
        "uploadHandler must pass a filepath.Base-sanitized filename joined to "
        "/app/server/uploads into its file-creation call"
    )


def test_benign_uploads_are_restored():
    marker = uuid.uuid4().hex
    for filename, payload in [
        (f"benign-{marker}.txt", b"ordinary upload content"),
        (f"evidence-{marker}.dat", b"second benign upload"),
    ]:
        destination = UPLOAD_ROOT / filename
        destination.unlink(missing_ok=True)
        response = requests.post(
            "http://localhost:8080/upload",
            files={"file": (filename, payload)},
            timeout=5,
        )
        assert 200 <= response.status_code < 300, (
            f"Benign upload {filename!r} was rejected with HTTP {response.status_code}"
        )
        assert destination.is_file(), f"Benign upload was not saved as {destination}"
        assert destination.read_bytes() == payload, "Benign upload contents were not preserved"


def assert_traversal_is_contained(filename, payload, outside_targets):
    for target in outside_targets:
        Path(target).unlink(missing_ok=True)

    before = {p for p in UPLOAD_ROOT.rglob("*") if p.is_file()}
    response = requests.post(
        "http://localhost:8080/upload",
        files={"file": (filename, payload)},
        timeout=5,
    )

    for target in outside_targets:
        assert not Path(target).exists(), f"Traversal wrote outside uploads: {target}"

    if 200 <= response.status_code < 300:
        matches = []
        for candidate in UPLOAD_ROOT.rglob("*"):
            if candidate.is_file() and candidate not in before:
                try:
                    if candidate.read_bytes() == payload:
                        matches.append(candidate)
                except OSError:
                    pass
        assert matches, f"Accepted upload {filename!r} was not written under the uploads directory"
        for match in matches:
            resolved = match.resolve()
            assert resolved.parent == UPLOAD_ROOT, (
                f"Accepted upload was not sanitized to a direct child of {UPLOAD_ROOT}: {resolved}"
            )


def test_server_upload_path_traversal_mitigation():
    url = "http://localhost:8080/upload"

    evil_file_path = "/tmp/evil.txt"
    if os.path.exists(evil_file_path):
        os.remove(evil_file_path)

    files = {'file': ('../../../tmp/evil.txt', b'malicious content')}

    try:
        requests.post(url, files=files, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the Go server at {url}. Error: {e}")

    assert not os.path.exists(evil_file_path), "Path traversal vulnerability still exists! File was written to /tmp/evil.txt"


def test_multiple_traversal_forms_remain_contained():
    marker = uuid.uuid4().hex
    cases = [
        (f"../../../tmp/traversal-{marker}.txt", [f"/tmp/traversal-{marker}.txt"]),
        (f"../../app-level-{marker}.txt", [f"/app/app-level-{marker}.txt"]),
        (f"../server-level-{marker}.txt", [f"/app/server/server-level-{marker}.txt"]),
        (f"../../../../root-level-{marker}.txt", [f"/root-level-{marker}.txt"]),
        (f"/tmp/absolute-{marker}.txt", [f"/tmp/absolute-{marker}.txt"]),
        (f"..\\..\\tmp\\backslash-{marker}.txt", [f"/tmp/backslash-{marker}.txt"]),
    ]
    for index, (filename, targets) in enumerate(cases):
        assert_traversal_is_contained(filename, f"payload-{marker}-{index}".encode(), targets)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
