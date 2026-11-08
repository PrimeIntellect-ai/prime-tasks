#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

WORKSPACE = "/home/user/artifact_cache"
BINARY = WORKSPACE + "/verifier/target/debug/verifier"
LOG = "/home/user/test_results.log"


def test_rust_verifier_compiled_and_works():
    build = subprocess.run(
        ["cargo", "build", "--quiet"],
        cwd=WORKSPACE + "/verifier",
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert build.returncode == 0, build.stdout + build.stderr
    assert os.path.isfile(BINARY), f"Rust verifier binary not found at {BINARY}. Did you compile it?"
    assert os.stat(BINARY).st_mode & stat.S_IXUSR, "Rust verifier is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Verifier is not a compiled ELF binary"

    proc_valid = subprocess.run([BINARY, "core-test"], capture_output=True)
    assert proc_valid.returncode == 0, "Verifier should exit with 0 for 'core-test'"

    proc_invalid = subprocess.run([BINARY, "malicious"], capture_output=True)
    assert proc_invalid.returncode != 0, "Verifier should exit with non-zero for 'malicious'"

    token = uuid.uuid4().hex
    valid_names = [
        "core-" + token,
        "core-package-" + token,
        "core-" + token + ".tar.gz",
        "core-",
    ]
    invalid_names = [
        token,
        "xcore-" + token,
        "Core-" + token,
        "cor-" + token,
        "pre-core-" + token,
        "",
    ]
    for name in valid_names:
        result = subprocess.run([BINARY, name], capture_output=True, timeout=10)
        assert result.returncode == 0, f"Verifier rejected valid generated artifact {name!r}"
    for name in invalid_names:
        result = subprocess.run([BINARY, name], capture_output=True, timeout=10)
        assert result.returncode != 0, f"Verifier accepted invalid generated artifact {name!r}"
    assert subprocess.run([BINARY], capture_output=True, timeout=10).returncode != 0


def test_test_results_log_exists_and_passed_and_fixtures_run():
    try:
        os.remove(LOG)
    except FileNotFoundError:
        pass

    with open(LOG, "w") as output:
        run = subprocess.run(
            [sys.executable, "-m", "pytest", WORKSPACE + "/test_proxy.py", "-v"],
            cwd=WORKSPACE,
            stdout=output,
            stderr=subprocess.STDOUT,
            timeout=90,
        )
    assert run.returncode == 0, "The submitted pytest suite did not pass; see /home/user/test_results.log"
    assert os.path.isfile(LOG), f"Test results log not found at {LOG}"
    with open(LOG, "r") as f:
        content = f.read()
    assert re.search(r"\b\d+ passed\b", content), "The test results log does not indicate that tests passed."

    # Exercise the submitted fixtures from an independent generated test, rather
    # than trusting tests or output supplied by the submission.
    token = uuid.uuid4().hex
    artifact = "core-fixture-" + token
    artifact_path = WORKSPACE + "/backend_storage/artifacts/" + artifact
    expected = "fixture-data-" + token
    with open(artifact_path, "w") as f:
        f.write(expected)
    validation = '''
import os
import urllib.request
from test_proxy import mock_backend, proxy_server

def test_submitted_fixtures(mock_backend, proxy_server):
    artifact = os.environ["FIXTURE_ARTIFACT"]
    expected = os.environ["FIXTURE_EXPECTED"].encode()
    with urllib.request.urlopen("http://localhost:8080/download/" + artifact, timeout=10) as response:
        assert response.status == 200
        assert response.read().strip() == expected
'''
    with open("/tmp/test_submitted_fixtures.py", "w") as f:
        f.write(validation)
    env = os.environ.copy()
    env["PYTHONPATH"] = WORKSPACE
    env["FIXTURE_ARTIFACT"] = artifact
    env["FIXTURE_EXPECTED"] = expected
    try:
        fixture_run = subprocess.run(
            [sys.executable, "-m", "pytest", "/tmp/test_submitted_fixtures.py", "-q"],
            cwd=WORKSPACE,
            env=env,
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert fixture_run.returncode == 0, fixture_run.stdout + fixture_run.stderr
    finally:
        try:
            os.remove(artifact_path)
        except FileNotFoundError:
            pass


def test_proxy_behavior():
    sys.path.insert(0, WORKSPACE)
    try:
        from proxy import ProxyHandler
    except ImportError:
        assert False, "Could not import ProxyHandler from proxy.py"

    token = uuid.uuid4().hex
    responses = {
        "/artifacts/core-linux.tar.gz": (200, b"dummy-data\n"),
        "/artifacts/core-" + token: (207, ("dynamic-" + token).encode()),
        "/artifacts/core-range-" + token: (206, b"partial\x00content-" + token.encode()),
        "/artifacts/core-missing-" + token: (410, ("gone-" + token).encode()),
    }
    backend_requests = []

    class BackendHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            backend_requests.append(self.path)
            status, body = responses.get(self.path, (404, b"backend-not-found"))
            self.send_response(status)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    class ReusableHTTPServer(HTTPServer):
        allow_reuse_address = True

    real_binary = BINARY + ".verifier-test-real"
    spy_log = "/tmp/verifier-invocations-" + token
    if os.path.exists(real_binary):
        os.remove(real_binary)
    os.rename(BINARY, real_binary)
    with open(BINARY, "w") as f:
        f.write("#!/bin/sh\nprintf '%s\\n' \"$1\" >> " + spy_log + "\nexec " + real_binary + " \"$@\"\n")
    os.chmod(BINARY, 0o755)

    backend_server = None
    proxy_server = None
    try:
        backend_server = ReusableHTTPServer(("localhost", 8081), BackendHandler)
        backend_thread = threading.Thread(target=backend_server.serve_forever, daemon=True)
        backend_thread.start()

        proxy_server = ReusableHTTPServer(("localhost", 8080), ProxyHandler)
        proxy_thread = threading.Thread(target=proxy_server.serve_forever, daemon=True)
        proxy_thread.start()
        time.sleep(0.3)

        def request(artifact):
            url = "http://localhost:8080/download/" + artifact
            try:
                with urllib.request.urlopen(url, timeout=10) as response:
                    return response.status, response.read()
            except urllib.error.HTTPError as error:
                return error.code, error.read()

        # Preserve the original fixed behavior checks.
        status, body = request("core-linux.tar.gz")
        assert status == 200, "Valid artifact should return 200"
        assert body.decode().strip() == "dummy-data"
        status, body = request("malicious.sh")
        assert status == 403, f"Expected 403 Forbidden, got {status}"
        assert body == b"Invalid artifact"

        # Generated names and varied backend statuses/content prevent a fixed-case proxy.
        generated = [
            ("core-" + token, 207, ("dynamic-" + token).encode()),
            ("core-range-" + token, 206, b"partial\x00content-" + token.encode()),
            ("core-missing-" + token, 410, ("gone-" + token).encode()),
        ]
        for artifact, expected_status, expected_body in generated:
            status, body = request(artifact)
            assert status == expected_status, (artifact, status, expected_status)
            assert body == expected_body, (artifact, body, expected_body)

        invalid = [token, "xcore-" + token, "Core-" + token, "pre-core-" + token]
        for artifact in invalid:
            status, body = request(artifact)
            assert status == 403, f"Invalid generated artifact {artifact!r} returned {status}"
            assert body == b"Invalid artifact"
            assert "/artifacts/" + artifact not in backend_requests, "Rejected artifact reached backend"

        requested_artifacts = ["core-linux.tar.gz", "malicious.sh"] + [x[0] for x in generated] + invalid
        with open(spy_log, "r") as f:
            invocations = [line.rstrip("\n") for line in f]
        for artifact in requested_artifacts:
            assert artifact in invocations, f"Proxy did not invoke the required verifier binary for {artifact!r}"
    finally:
        if proxy_server is not None:
            proxy_server.shutdown()
            proxy_server.server_close()
        if backend_server is not None:
            backend_server.shutdown()
            backend_server.server_close()
        if os.path.exists(BINARY):
            os.remove(BINARY)
        if os.path.exists(real_binary):
            os.rename(real_binary, BINARY)
        try:
            os.remove(spy_log)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
