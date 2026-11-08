#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import http.client
import os
import signal
import socket
import subprocess
import tempfile
import time


def test_server_fixed_go():
    path = "/home/user/server_fixed.go"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    expected_header = "default-src 'self'; script-src 'none';"
    assert "Content-Security-Policy" in content, "Content-Security-Policy header is missing in server_fixed.go."
    assert expected_header in content, f"The CSP header value should be exactly: {expected_header}"
    expected_body = "<html><body><h1>Admin Dashboard</h1></body></html>"
    assert expected_body in content, "The original HTTP response body must not be changed."

    # Ensure an unrelated process cannot satisfy the HTTP checks.
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.settimeout(0.5)
    try:
        assert probe.connect_ex(("127.0.0.1", 8080)) != 0, "Port 8080 is already occupied before starting server_fixed.go."
    finally:
        probe.close()

    with tempfile.TemporaryDirectory() as tmpdir:
        binary = os.path.join(tmpdir, "server_fixed")
        build = subprocess.run(
            ["go", "build", "-o", binary, path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, f"server_fixed.go does not compile:\n{build.stderr}"

        proc = subprocess.Popen(
            [binary],
            cwd=tmpdir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            preexec_fn=os.setsid,
        )
        try:
            response = None
            last_error = None
            deadline = time.time() + 10
            while time.time() < deadline:
                assert proc.poll() is None, "The compiled server exited before serving HTTP requests."
                conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=1)
                try:
                    conn.request("GET", "/")
                    response = conn.getresponse()
                    status = response.status
                    headers = response.getheaders()
                    body = response.read().decode("utf-8")
                    break
                except (ConnectionError, OSError) as exc:
                    last_error = exc
                    time.sleep(0.1)
                finally:
                    conn.close()

            assert response is not None, f"The compiled server did not accept HTTP requests: {last_error}"
            assert status == 200, f"Expected HTTP status 200, got {status}."
            csp_values = [value for name, value in headers if name.lower() == "content-security-policy"]
            assert csp_values == [expected_header], f"Expected exactly one Content-Security-Policy header with value '{expected_header}', got {csp_values}."
            assert body == expected_body, f"The HTTP response body was changed. Got: {body!r}"
        finally:
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGTERM)
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait(timeout=3)


def test_decrypted_secret():
    path = "/home/user/decrypted_secret.txt"
    assert os.path.isfile(path), f"File {path} is missing. Did you successfully decrypt the secret?"

    with open(path, "r") as f:
        content = f.read()

    expected_secret = "FLAG{aud1t_p4ss3d_c5p_a3s}"
    assert content == expected_secret, f"The decrypted secret is incorrect. Expected exactly '{expected_secret}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
