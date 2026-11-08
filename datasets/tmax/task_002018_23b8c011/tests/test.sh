#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import http.server
import os
import pathlib
import secrets
import subprocess
import threading
import time

import pytest

APP = "/home/user/app"
VENV_PYTHON = f"{APP}/venv/bin/python"
SOURCE_ROOT = pathlib.Path(f"{APP}/urllib3-src/src").resolve()


def test_latest_logs_symlink():
    """Check that latest_logs points to the services log directory."""
    symlink_path = f"{APP}/latest_logs"
    target_path = f"{APP}/services/logs"

    assert os.path.islink(symlink_path), f"Expected {symlink_path} to be a symbolic link."
    actual_target = os.readlink(symlink_path)
    absolute_target = os.path.normpath(os.path.join(os.path.dirname(symlink_path), actual_target))
    assert absolute_target == target_path, (
        f"Symlink {symlink_path} points to {absolute_target}, expected {target_path}."
    )


def test_perturbation_removed():
    """Verify that the artificial delay is absent from the vendored source."""
    connection_py = f"{APP}/urllib3-src/src/urllib3/connection.py"
    assert os.path.isfile(connection_py), f"Vendored urllib3 source file missing at {connection_py}."

    with open(connection_py, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "time.sleep(0.5)" not in content, (
        "The artificial delay 'time.sleep(0.5)' is still present in connection.py."
    )

    # Also reject equivalent direct sleep spellings in connection.py. The behavioral
    # test below remains authoritative for aliases or other ways of implementing a delay.
    tree = ast.parse(content, filename=connection_py)
    sleep_calls = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if (isinstance(func, ast.Name) and func.id == "sleep") or (
            isinstance(func, ast.Attribute) and func.attr == "sleep"
        ):
            sleep_calls.append(node.lineno)
    assert not sleep_calls, f"Sleep call(s) remain in connection.py at lines {sleep_calls}."


def _find_db_service_processes():
    matches = []
    for entry in pathlib.Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            raw = (entry / "cmdline").read_bytes()
            args = [part.decode(errors="replace") for part in raw.split(b"\0") if part]
            if not args or not any(
                os.path.basename(arg) == "user_db_service.py" for arg in args
            ):
                continue

            environ_raw = (entry / "environ").read_bytes()
            environ = {}
            for item in environ_raw.split(b"\0"):
                if b"=" in item:
                    key, value = item.split(b"=", 1)
                    environ[key.decode(errors="replace")] = value.decode(errors="replace")

            argv0 = args[0]
            if os.path.isabs(argv0):
                invoked_from_venv = os.path.normpath(argv0) == VENV_PYTHON
            else:
                cwd = os.readlink(entry / "cwd")
                invoked_from_venv = os.path.normpath(os.path.join(cwd, argv0)) == VENV_PYTHON

            invoked_from_venv = invoked_from_venv or (
                os.path.normpath(environ.get("VIRTUAL_ENV", "")) == f"{APP}/venv"
            )
            matches.append((int(entry.name), invoked_from_venv, args))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return matches


def test_db_service_is_running_from_venv():
    """The DB service must remain running (or have been restarted) under the app venv."""
    matches = _find_db_service_processes()
    assert matches, "The User DB Service is not running."
    assert any(item[1] for item in matches), (
        "The User DB Service is running, but not from /home/user/app/venv."
    )


def test_venv_worker_and_installed_urllib3_performance():
    """Execute the worker and independently exercise the venv-installed package."""
    worker = f"{APP}/services/sync_worker.py"
    assert os.path.isfile(worker), f"Sync Worker is missing at {worker}."

    # Execute the actual worker using the required virtual environment. This checks
    # that a freshly started worker can load and use the patched installation.
    try:
        worker_result = subprocess.run(
            [VENV_PYTHON, worker],
            capture_output=True,
            text=True,
            timeout=5.0,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The restarted Sync Worker timed out.")
    assert worker_result.returncode == 0, (
        f"Sync Worker failed with exit code {worker_result.returncode}: "
        f"{worker_result.stderr}"
    )

    token = secrets.token_hex(16).encode("ascii")
    state = {"count": 0}
    lock = threading.Lock()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            with lock:
                state["count"] += 1
            self.send_response(200)
            self.send_header("Content-Length", str(len(token)))
            self.end_headers()
            self.wfile.write(token)

        def log_message(self, format, *args):
            pass

    try:
        server = http.server.ThreadingHTTPServer(("127.0.0.2", 0), Handler)
    except OSError as exc:
        pytest.fail(f"Could not create verifier loopback server: {exc}")

    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = server.server_address[1]

    client_code = r'''
import pathlib
import sys
import urllib3

source_root = pathlib.Path(sys.argv[1]).resolve()
module_path = pathlib.Path(urllib3.__file__).resolve()
try:
    module_path.relative_to(source_root)
except ValueError:
    raise SystemExit("urllib3 was not imported from the vendored installation: " + str(module_path))

url = sys.argv[2]
expected = sys.argv[3].encode("ascii")
http = urllib3.PoolManager()
for _ in range(20):
    response = http.request("GET", url)
    if response.status != 200 or response.data != expected:
        raise SystemExit("unexpected response from verifier server")
'''

    started = time.perf_counter()
    try:
        result = subprocess.run(
            [
                VENV_PYTHON,
                "-c",
                client_code,
                str(SOURCE_ROOT),
                f"http://127.0.0.2:{port}/sync",
                token.decode("ascii"),
            ],
            capture_output=True,
            text=True,
            timeout=15.0,
        )
        runtime = time.perf_counter() - started
    except subprocess.TimeoutExpired:
        pytest.fail("Twenty requests through the venv-installed urllib3 timed out.")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2.0)

    assert result.returncode == 0, (
        f"The venv-installed urllib3 test failed: {result.stderr or result.stdout}"
    )
    assert state["count"] == 20, (
        f"Expected 20 real loopback requests, but the verifier server received {state['count']}."
    )
    assert runtime <= 1.0, (
        f"Performance metric failed: runtime was {runtime:.3f} seconds, expected <= 1.0 seconds."
    )


def test_original_benchmark_assertion():
    """Retain the original benchmark/file assertion in addition to the trusted test."""
    benchmark_script = "/home/user/verifier_benchmark.py"
    assert os.path.isfile(benchmark_script), f"Benchmark script {benchmark_script} is missing."

    try:
        result = subprocess.run(
            ["python3", benchmark_script],
            capture_output=True,
            text=True,
            check=True,
            timeout=15.0,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Benchmark script timed out after 15 seconds.")
    except subprocess.CalledProcessError as exc:
        pytest.fail(
            f"Benchmark script failed with exit code {exc.returncode}. Stderr: {exc.stderr}"
        )

    output = result.stdout.strip()
    try:
        runtime = float(output)
    except ValueError:
        pytest.fail(f"Benchmark script returned non-float output: {output}")
    assert runtime <= 1.0, (
        f"Performance metric failed: runtime was {runtime:.3f} seconds, expected <= 1.0 seconds."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
