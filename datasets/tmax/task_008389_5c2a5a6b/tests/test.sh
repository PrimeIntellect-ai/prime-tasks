#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import http.client
import json
import os
import stat
import subprocess
import tempfile
import time

import pytest

AUDIT_TRAIL_PATH = "/home/user/audit_trail.json"
SERVER_GO_PATH = "/home/user/app/server.go"
SERVER_BIN_PATH = "/home/user/app/server"
SANDBOX_SH_PATH = "/home/user/sandbox.sh"
EXPECTED_CSP = "default-src 'self'; script-src 'none'; object-src 'none';"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def stop_existing_server():
    subprocess.run(["pkill", "-x", "server"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.2)


def exercise_server(binary):
    stop_existing_server()
    proc = subprocess.Popen([binary], cwd="/home/user/app",
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        deadline = time.time() + 5
        while True:
            if proc.poll() is not None:
                out, err = proc.communicate()
                pytest.fail(f"Server exited before accepting connections: {out!r} {err!r}")
            try:
                conn = http.client.HTTPConnection("127.0.0.1", 8443, timeout=0.5)
                conn.request("GET", "/")
                response = conn.getresponse()
                response.read()
                assert response.getheader("Content-Security-Policy") == EXPECTED_CSP
                conn.close()
                break
            except (OSError, http.client.HTTPException):
                if time.time() >= deadline:
                    pytest.fail("Server did not begin listening on 127.0.0.1:8443")
                time.sleep(0.1)

        for method, path in [("GET", "/missing"), ("HEAD", "/"), ("POST", "/anything")]:
            conn = http.client.HTTPConnection("127.0.0.1", 8443, timeout=2)
            conn.request(method, path, body=b"test" if method == "POST" else None)
            response = conn.getresponse()
            response.read()
            values = response.headers.get_all("Content-Security-Policy") or []
            assert values == [EXPECTED_CSP], (
                f"{method} {path} did not return exactly the required CSP header: {values!r}"
            )
            conn.close()
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
        stop_existing_server()


def test_audit_trail_json():
    assert os.path.exists(AUDIT_TRAIL_PATH), f"{AUDIT_TRAIL_PATH} does not exist."
    with open(AUDIT_TRAIL_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{AUDIT_TRAIL_PATH} is not valid JSON.")

    assert data.get("listening_port") == 8443, "listening_port in audit_trail.json is incorrect."
    assert data.get("vulnerability_cwe") == "CWE-330", "vulnerability_cwe in audit_trail.json is incorrect."
    assert data.get("remediation_action") == "Applied CSP and Sandboxing", "remediation_action in audit_trail.json is incorrect."


def test_server_go_csp_header():
    assert os.path.exists(SERVER_GO_PATH), f"{SERVER_GO_PATH} does not exist."
    with open(SERVER_GO_PATH, "r") as f:
        content = f.read()

    assert "Content-Security-Policy" in content, "CSP header name not found in server.go"
    assert "default-src 'self'" in content, "CSP header default-src directive missing or incorrect"
    assert "script-src 'none'" in content, "CSP header script-src directive missing or incorrect"
    assert "object-src 'none'" in content, "CSP header object-src directive missing or incorrect"


def test_server_binary_compiled_and_enforces_csp():
    assert os.path.exists(SERVER_BIN_PATH), f"{SERVER_BIN_PATH} does not exist. Did you compile the Go server?"
    assert os.access(SERVER_BIN_PATH, os.X_OK), f"{SERVER_BIN_PATH} is not executable."

    rebuilt = "/tmp/rebuilt_server"
    subprocess.run(["go", "build", "-o", rebuilt, "server.go"],
                   cwd="/home/user/app", check=True, timeout=60)
    assert sha256(SERVER_BIN_PATH) == sha256(rebuilt), (
        "The submitted server binary is stale or was not built from the submitted server.go."
    )

    exercise_server(rebuilt)
    exercise_server(SERVER_BIN_PATH)


def test_sandbox_sh():
    assert os.path.exists(SANDBOX_SH_PATH), f"{SANDBOX_SH_PATH} does not exist."

    st = os.stat(SANDBOX_SH_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"{SANDBOX_SH_PATH} is not executable."

    with open(SANDBOX_SH_PATH, "r") as f:
        content = f.read()

    assert "bwrap" in content, "bwrap command not found in sandbox.sh"
    assert "--ro-bind / /" in content or ("--ro-bind" in content and "/" in content), "--ro-bind / / missing in sandbox.sh"
    assert "--bind /home/user/app /home/user/app" in content or ("--bind" in content and "/home/user/app" in content), "--bind /home/user/app /home/user/app missing in sandbox.sh"
    assert "--unshare-net" in content, "--unshare-net missing in sandbox.sh"
    assert "--chdir /home/user/app" in content or "cd /home/user/app" in content, "Must change directory to /home/user/app before or during bwrap execution."
    assert "./server" in content or "/home/user/app/server" in content, "Must execute the server binary in the bwrap command."

    with tempfile.TemporaryDirectory() as shim_dir:
        log_path = os.path.join(shim_dir, "invocation.json")
        shim_path = os.path.join(shim_dir, "bwrap")
        with open(shim_path, "w") as f:
            f.write("#!/usr/bin/env python3\n")
            f.write("import json, os, sys\n")
            f.write("with open(os.environ['BWRAP_TEST_LOG'], 'w') as out:\n")
            f.write("    json.dump({'argv': sys.argv[1:], 'cwd': os.getcwd()}, out)\n")
        os.chmod(shim_path, 0o755)

        env = os.environ.copy()
        env["PATH"] = shim_dir + os.pathsep + env.get("PATH", "")
        env["BWRAP_TEST_LOG"] = log_path
        result = subprocess.run([SANDBOX_SH_PATH], cwd="/home/user", env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, timeout=10)
        assert result.returncode == 0, f"sandbox.sh failed when executed: {result.stderr}"
        assert os.path.exists(log_path), "sandbox.sh did not actually invoke bwrap."

        with open(log_path, "r") as f:
            invocation = json.load(f)
        argv = invocation["argv"]

        server_positions = [i for i, arg in enumerate(argv)
                            if arg in ("./server", "/home/user/app/server")]
        assert server_positions, "bwrap was not invoked to execute the server binary."
        command_index = server_positions[0]
        options = argv[:command_index]

        assert any(options[i:i+3] == ["--ro-bind", "/", "/"]
                   for i in range(max(0, len(options) - 2))), (
            "bwrap was not invoked with the required read-only root bind."
        )
        assert any(options[i:i+3] == ["--bind", "/home/user/app", "/home/user/app"]
                   for i in range(max(0, len(options) - 2))), (
            "bwrap was not invoked with the required read-write app bind."
        )
        assert "--unshare-net" in options, "bwrap was not invoked with an unshared network namespace."

        has_chdir = any(options[i:i+2] == ["--chdir", "/home/user/app"]
                        for i in range(max(0, len(options) - 1)))
        assert has_chdir or invocation["cwd"] == "/home/user/app", (
            "sandbox.sh did not change to /home/user/app before executing ./server."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
