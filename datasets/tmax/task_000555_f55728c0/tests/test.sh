#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import http.server
import json
import os
import shlex
import signal
import socket
import subprocess
import threading
import time
import uuid

import pytest

APP = "/home/user/app"
PROCESS = f"{APP}/process_metrics.sh"
E2E = f"{APP}/run_e2e.sh"
EXPECTED = f"{APP}/tests/expected.txt"
ACTUAL = f"{APP}/tests/actual.txt"
DATA = f"{APP}/data/access.jsonl"


def run_with_timeout(argv, cwd=APP, timeout=20):
    proc = subprocess.Popen(
        argv,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        stdout, stderr = proc.communicate()
        pytest.fail(
            f"Command timed out: {argv}\nStdout: {stdout}\nStderr: {stderr}"
        )
    return subprocess.CompletedProcess(argv, proc.returncode, stdout, stderr)


def port_8000_open():
    try:
        with socket.create_connection(("127.0.0.1", 8000), timeout=0.2):
            return True
    except OSError:
        return False


def test_process_metrics_exists_and_executable():
    """Verify that process_metrics.sh exists and is executable."""
    assert os.path.isfile(PROCESS), f"Script missing: {PROCESS} was not created."
    assert os.access(PROCESS, os.X_OK), f"Script not executable: {PROCESS} lacks execute permissions."


def test_run_e2e_exists_and_executable():
    """Verify that run_e2e.sh exists and is executable."""
    assert os.path.isfile(E2E), f"Script missing: {E2E} was not created."
    assert os.access(E2E, os.X_OK), f"Script not executable: {E2E} lacks execute permissions."


def test_expected_txt_is_patched():
    """Verify that expected.txt has been updated to the new format via the patch."""
    assert os.path.isfile(EXPECTED), f"File missing: {EXPECTED} does not exist."

    with open(EXPECTED, "r") as f:
        content = f.read().strip()

    assert "/home,3" in content, "expected.txt does not contain the new patched format (e.g., '/home,3')."
    assert "3 /home" not in content, "expected.txt still contains the old format (e.g., '3 /home'). Did you apply the patch?"
    assert content == "/home,3\n/about,2\n/api/login,2", (
        "expected.txt does not exactly contain the result of format_update.patch."
    )


def test_process_metrics_on_independent_http_input():
    """Exercise process_metrics.sh against unpredictable JSONL served over HTTP."""
    token = uuid.uuid4().hex
    paths = {
        "alpha": f"/alpha-{token}",
        "middle": f"/middle-{token}",
        "zeta": f"/zeta-{token}",
        "error": f"/error-{token}",
    }
    records = [
        {"path": paths["zeta"], "status": 200},
        {"path": paths["alpha"], "status": 399},
        {"path": paths["middle"], "status": 201},
        {"path": paths["zeta"], "status": 204},
        {"path": paths["alpha"], "status": 200},
        {"path": paths["middle"], "status": 302},
        {"path": paths["zeta"], "status": -1},
        {"path": paths["alpha"], "status": 0},
        {"path": paths["error"], "status": 400},
        {"path": paths["alpha"], "status": 401},
        {"path": paths["zeta"], "status": 500},
    ]
    payload = "".join(json.dumps(record) + "\n" for record in records).encode()
    request_count = [0]

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            request_count[0] += 1
            if self.path != "/metrics.jsonl":
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "application/x-ndjson")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, fmt, *args):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        url = f"http://127.0.0.1:{server.server_port}/metrics.jsonl"
        result = run_with_timeout([PROCESS, url])
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    counts = collections.Counter(
        record["path"] for record in records if record["status"] < 400
    )
    expected_output = "".join(
        f"{path},{count}\n"
        for path, count in sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    )
    assert result.returncode == 0, (
        f"process_metrics.sh failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert request_count[0] > 0, "process_metrics.sh did not fetch the supplied HTTP URL."
    assert result.stdout == expected_output, (
        "process_metrics.sh produced incorrect filtering, aggregation, formatting, or sorting.\n"
        f"Actual:\n{result.stdout}\nExpected:\n{expected_output}"
    )


def test_run_e2e_really_orchestrates_http_processing():
    """Ensure run_e2e starts the server, invokes the processor, redirects output, compares, and stops the server."""
    assert not port_8000_open(), "TCP port 8000 was already in use before run_e2e.sh was tested."

    token = uuid.uuid4().hex
    sentinel = f"/tmp/e2e-called-{token}"
    fetched = f"/tmp/e2e-fetched-{token}"
    probe_output = f"/probe-{token},1\n"
    served_data = (f'{{"path":"/served-{token}","status":200}}\n').encode()

    with open(PROCESS, "rb") as f:
        process_backup = f.read()
    process_mode = os.stat(PROCESS).st_mode
    with open(EXPECTED, "rb") as f:
        expected_backup = f.read()
    with open(DATA, "rb") as f:
        data_backup = f.read()
    actual_existed = os.path.exists(ACTUAL)
    actual_backup = open(ACTUAL, "rb").read() if actual_existed else None

    probe = f"""#!/bin/bash
set -e
[ \"$#\" -eq 1 ]
printf '%s' \"$1\" > {shlex.quote(sentinel)}
curl -fsS \"$1\" > {shlex.quote(fetched)}
printf '%s' {shlex.quote(probe_output)}
"""

    try:
        with open(PROCESS, "w") as f:
            f.write(probe)
        os.chmod(PROCESS, 0o755)
        with open(DATA, "wb") as f:
            f.write(served_data)
        with open(EXPECTED, "w") as f:
            f.write(probe_output)
        if os.path.exists(ACTUAL):
            os.unlink(ACTUAL)

        result = run_with_timeout([E2E])
        assert result.returncode == 0, (
            f"run_e2e.sh failed its orchestration probe with exit code {result.returncode}.\n"
            f"Stdout: {result.stdout}\nStderr: {result.stderr}"
        )
        assert os.path.isfile(sentinel), "run_e2e.sh never invoked process_metrics.sh."
        with open(sentinel) as f:
            invoked_url = f.read()
        assert invoked_url == "http://localhost:8000/access.jsonl", (
            f"run_e2e.sh invoked process_metrics.sh with the wrong URL: {invoked_url!r}"
        )
        assert os.path.isfile(fetched), "The processor probe could not fetch the served access.jsonl."
        with open(fetched, "rb") as f:
            assert f.read() == served_data, "run_e2e.sh did not serve the app data directory correctly."
        with open(ACTUAL) as f:
            assert f.read() == probe_output, "run_e2e.sh did not redirect processor stdout to actual.txt."
        with open(EXPECTED) as f:
            assert f.read() == probe_output, "run_e2e.sh improperly modified expected.txt."

        for _ in range(30):
            if not port_8000_open():
                break
            time.sleep(0.1)
        assert not port_8000_open(), "run_e2e.sh left its HTTP server running after completion."
    finally:
        with open(PROCESS, "wb") as f:
            f.write(process_backup)
        os.chmod(PROCESS, process_mode)
        with open(EXPECTED, "wb") as f:
            f.write(expected_backup)
        with open(DATA, "wb") as f:
            f.write(data_backup)
        if actual_existed:
            with open(ACTUAL, "wb") as f:
                f.write(actual_backup)
        elif os.path.exists(ACTUAL):
            os.unlink(ACTUAL)
        for path in (sentinel, fetched):
            if os.path.exists(path):
                os.unlink(path)


def test_run_e2e_succeeds():
    """Verify that run_e2e.sh runs successfully and exits with code 0."""
    result = run_with_timeout([E2E])

    assert result.returncode == 0, (
        f"run_e2e.sh failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\n"
        f"Stderr: {result.stderr}"
    )


def test_actual_matches_expected():
    """Verify that actual.txt exactly matches expected.txt after running the E2E script."""
    assert os.path.isfile(ACTUAL), f"File missing: {ACTUAL} was not generated."

    with open(ACTUAL, "r") as f:
        actual_content = f.read().strip()

    with open(EXPECTED, "r") as f:
        expected_content = f.read().strip()

    assert actual_content == expected_content, (
        "actual.txt does not match expected.txt.\n"
        f"Actual output:\n{actual_content}\n\n"
        f"Expected output:\n{expected_content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
