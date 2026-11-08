#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

# Verify the vendored source is repaired, builds, and produced the submitted binary.
test -f /app/vendored/ffuf/main.go
! grep -q 'flag\.Prase' /app/vendored/ffuf/main.go
rm -f /tmp/ffuf_rebuilt
(
    cd /app/vendored/ffuf
    go build -mod=vendor -o /tmp/ffuf_rebuilt
)
test -x /home/user/ffuf_fixed
cmp -s /tmp/ffuf_rebuilt /home/user/ffuf_fixed

# Check the gateway source structurally for os/exec and a PID-namespace
# configuration on Cmd.SysProcAttr.
test -f /home/user/sec_gateway.go
cat <<'CHECK_EOF' > /tmp/check_gateway_source.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)

func selectorIs(e ast.Expr, pkg, name string) bool {
    s, ok := e.(*ast.SelectorExpr)
    if !ok || s.Sel.Name != name {
        return false
    }
    x, ok := s.X.(*ast.Ident)
    return ok && x.Name == pkg
}

func containsCloneNewPID(e ast.Expr, syscallName string) bool {
    found := false
    ast.Inspect(e, func(n ast.Node) bool {
        if x, ok := n.(ast.Expr); ok && selectorIs(x, syscallName, "CLONE_NEWPID") {
            found = true
        }
        return true
    })
    return found
}

func validSysProcAttr(e ast.Expr, syscallName string) bool {
    valid := false
    ast.Inspect(e, func(n ast.Node) bool {
        cl, ok := n.(*ast.CompositeLit)
        if !ok || !selectorIs(cl.Type, syscallName, "SysProcAttr") {
            return true
        }
        for _, elt := range cl.Elts {
            kv, ok := elt.(*ast.KeyValueExpr)
            if !ok {
                continue
            }
            key, ok := kv.Key.(*ast.Ident)
            if ok && key.Name == "Cloneflags" && containsCloneNewPID(kv.Value, syscallName) {
                valid = true
            }
        }
        return true
    })
    return valid
}

func main() {
    fset := token.NewFileSet()
    f, err := parser.ParseFile(fset, "/home/user/sec_gateway.go", nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    execName, syscallName := "", ""
    for _, imp := range f.Imports {
        path := imp.Path.Value
        name := ""
        if imp.Name != nil {
            name = imp.Name.Name
        }
        if path == "\"os/exec\"" {
            if name == "" { name = "exec" }
            execName = name
        }
        if path == "\"syscall\"" {
            if name == "" { name = "syscall" }
            syscallName = name
        }
    }
    if execName == "" || syscallName == "" || execName == "." || syscallName == "." {
        fmt.Fprintln(os.Stderr, "gateway must import os/exec and syscall")
        os.Exit(1)
    }

    execUsed, namespaceConfigured := false, false
    ast.Inspect(f, func(n ast.Node) bool {
        if s, ok := n.(*ast.SelectorExpr); ok {
            if x, ok := s.X.(*ast.Ident); ok && x.Name == execName {
                execUsed = true
            }
        }

        if a, ok := n.(*ast.AssignStmt); ok {
            for i, lhs := range a.Lhs {
                s, ok := lhs.(*ast.SelectorExpr)
                if !ok || s.Sel.Name != "SysProcAttr" || len(a.Rhs) == 0 {
                    continue
                }
                rhs := a.Rhs[len(a.Rhs)-1]
                if i < len(a.Rhs) { rhs = a.Rhs[i] }
                if validSysProcAttr(rhs, syscallName) {
                    namespaceConfigured = true
                }
            }
        }

        if cl, ok := n.(*ast.CompositeLit); ok {
            for _, elt := range cl.Elts {
                kv, ok := elt.(*ast.KeyValueExpr)
                if !ok { continue }
                key, ok := kv.Key.(*ast.Ident)
                if ok && key.Name == "SysProcAttr" && validSysProcAttr(kv.Value, syscallName) {
                    namespaceConfigured = true
                }
            }
        }
        return true
    })

    if !execUsed || !namespaceConfigured {
        fmt.Fprintln(os.Stderr, "gateway must use os/exec and configure Cmd.SysProcAttr Cloneflags with syscall.CLONE_NEWPID")
        os.Exit(1)
    }
}
CHECK_EOF
go run /tmp/check_gateway_source.go

# Build the gateway source itself, rather than trusting an unrelated server the
# submission may already have placed on the required ports.
go build -o /tmp/sec_gateway_verified /home/user/sec_gateway.go

# Stop processes currently listening on either required port.
python3 <<'PY'
import os, signal, time

ports = {8080, 8081}
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if len(fields) > 9 and fields[3] == "0A":
                    port = int(fields[1].split(":")[1], 16)
                    if port in ports:
                        inodes.add(fields[9])
    except FileNotFoundError:
        pass

pids = set()
for entry in os.listdir("/proc"):
    if not entry.isdigit() or int(entry) == os.getpid():
        continue
    fd_dir = f"/proc/{entry}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                pids.add(int(entry))
                break
    except OSError:
        pass

for pid in pids:
    try: os.kill(pid, signal.SIGTERM)
    except ProcessLookupError: pass
time.sleep(0.5)
for pid in pids:
    try: os.kill(pid, signal.SIGKILL)
    except ProcessLookupError: pass
PY

/tmp/sec_gateway_verified >/tmp/sec_gateway.log 2>&1 &
GW_PID=$!
cleanup() {
    kill "$GW_PID" 2>/dev/null || true
    wait "$GW_PID" 2>/dev/null || true
}
trap cleanup EXIT

python3 <<'PY'
import socket, time
for _ in range(50):
    ready = True
    for port in (8080, 8081):
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                pass
        except OSError:
            ready = False
            break
    if ready:
        raise SystemExit(0)
    time.sleep(0.1)
raise SystemExit("gateway built from sec_gateway.go did not bind both ports")
PY

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import socket
import hashlib
import binascii
import subprocess
import secrets
import requests
import pytest

BINARY = "/home/user/ffuf_fixed"

def test_binary_exists():
    assert os.path.isfile(BINARY), f"The binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"The file {BINARY} is not executable."

def test_binary_is_repaired_ffuf():
    res = subprocess.run([BINARY, "-V"], capture_output=True, text=True, timeout=5)
    assert res.returncode == 0
    assert res.stdout == "ffuf version: 2.0.0\n"

def test_http_interface():
    try:
        response = requests.get("http://127.0.0.1:8080/scan", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP interface on port 8080: {e}")
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    assert "ffuf version: 2.0.0" in response.text, f"Expected 'ffuf version: 2.0.0' in response, got: {response.text}"

def get_encrypted_payload(plaintext: bytes) -> str:
    key_hex = binascii.hexlify(b"0123456789abcdef0123456789abcdef").decode()
    iv_hex = binascii.hexlify(b"abcdef0123456789").decode()
    cmd = ["openssl", "enc", "-aes-256-cbc", "-K", key_hex, "-iv", iv_hex]
    res = subprocess.run(cmd, input=plaintext, capture_output=True, check=True)
    return binascii.hexlify(res.stdout).decode()

def tcp_request(payload: str) -> str:
    try:
        with socket.create_connection(("127.0.0.1", 8081), timeout=5) as s:
            s.settimeout(5)
            s.sendall((payload + "\n").encode())
            chunks = []
            while True:
                data = s.recv(1024)
                if not data:
                    break
                chunks.append(data)
                if b"\n" in data:
                    break
            return b"".join(chunks).decode().strip()
    except Exception as e:
        pytest.fail(f"Failed to communicate with TCP interface on port 8081: {e}")

def test_tcp_interface_valid():
    assert os.path.isfile(BINARY), "Cannot run TCP test: binary missing."
    with open(BINARY, "rb") as f:
        expected_hash = hashlib.sha256(f.read()).hexdigest()
    response = tcp_request(get_encrypted_payload(b"VERIFY_INTEGRITY"))
    assert response == expected_hash, f"Expected hash {expected_hash}, got {response}"

def test_tcp_interface_invalid():
    response = tcp_request("00112233445566778899aabbccddeeff")
    assert response == "INVALID", f"Expected 'INVALID' for bad payload, got {response}"

def test_tcp_interface_encrypted_wrong_plaintext():
    wrong = ("NOT_VALID_" + secrets.token_hex(12)).encode()
    response = tcp_request(get_encrypted_payload(wrong))
    assert response == "INVALID", f"Expected 'INVALID' for wrong plaintext, got {response}"

def test_gateway_executes_current_binary_and_hashes_current_file():
    # Replace the binary after the gateway has started. A random response and
    # changed digest prove the HTTP and TCP handlers do not hardcode the one
    # deterministic result present at submission time.
    token = "probe-" + secrets.token_hex(20)
    backup = BINARY + ".verifier_backup"
    probe = BINARY + ".verifier_probe"
    assert not os.path.exists(backup)
    os.rename(BINARY, backup)
    try:
        with open(probe, "w") as f:
            f.write("#!/bin/sh\n")
            f.write("if [ \"$#\" -ne 1 ] || [ \"$1\" != \"-V\" ]; then echo BAD_ARGS; exit 0; fi\n")
            f.write("printf '%s\\n' " + repr(token) + "\n")
        os.chmod(probe, 0o755)
        os.rename(probe, BINARY)

        response = requests.get("http://127.0.0.1:8080/scan", timeout=5)
        assert response.status_code == 200
        assert response.text.strip() == token, f"HTTP handler did not execute current ffuf_fixed with -V: {response.text!r}"

        with open(BINARY, "rb") as f:
            expected_hash = hashlib.sha256(f.read()).hexdigest()
        actual = tcp_request(get_encrypted_payload(b"VERIFY_INTEGRITY"))
        assert actual == expected_hash, f"TCP handler returned stale or hardcoded hash: {actual}"
    finally:
        try: os.unlink(probe)
        except FileNotFoundError: pass
        try: os.unlink(BINARY)
        except FileNotFoundError: pass
        os.rename(backup, BINARY)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
