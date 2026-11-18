#!/bin/bash
set -e
mkdir -p /logs/verifier

# Remove legitimate stack processes that may have been left behind by an earlier
# manual run so the required fixed ports can be tested deterministically.
pkill -f '[p]ython3.*http.server.*9090' 2>/dev/null || true
pkill -f '/home/user/app_deployment/bin/[p]roxy_server' 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import signal
import socket
import subprocess
import tempfile
import threading
import time

BASE_DIR = "/home/user/app_deployment"


def test_directories_exist():
    """Verify all required directories are created."""
    dirs = [
        "config", "src", "bin", "scripts", "logs", "mail", "storage", "container_data"
    ]
    for d in dirs:
        path = os.path.join(BASE_DIR, d)
        assert os.path.isdir(path), f"Directory missing: {path}"


def test_fstab_mock():
    """Verify fstab.mock format and contents."""
    fstab_path = os.path.join(BASE_DIR, "config", "fstab.mock")
    assert os.path.isfile(fstab_path), f"File missing: {fstab_path}"

    with open(fstab_path, "r") as f:
        content = f.read().strip()

    fields = re.split(r'\s+', content)
    assert len(fields) == 6, f"fstab.mock must have exactly 6 fields, found {len(fields)}"
    assert fields[0] == "/home/user/app_deployment/storage", "Incorrect file system field"
    assert fields[1] == "/home/user/app_deployment/container_data", "Incorrect mount point field"
    assert fields[2] == "none", "Incorrect type field"
    assert fields[3] == "bind", "Incorrect options field"
    assert fields[4] == "0", "Incorrect dump field"
    assert fields[5] == "0", "Incorrect pass field"


def test_storage_index_html():
    """Verify index.html in storage directory."""
    index_path = os.path.join(BASE_DIR, "storage", "index.html")
    assert os.path.isfile(index_path), f"File missing: {index_path}"
    with open(index_path, "r") as f:
        assert f.read().strip() == "DEPLOYMENT_SUCCESS", "index.html does not contain the expected text."


def test_proxy_c_exists():
    """Verify proxy.c exists."""
    proxy_c_path = os.path.join(BASE_DIR, "src", "proxy.c")
    assert os.path.isfile(proxy_c_path), f"File missing: {proxy_c_path}"


def test_proxy_server_executable():
    """Verify proxy_server is compiled and executable."""
    proxy_bin_path = os.path.join(BASE_DIR, "bin", "proxy_server")
    assert os.path.isfile(proxy_bin_path), f"Executable missing: {proxy_bin_path}"
    assert os.access(proxy_bin_path, os.X_OK), f"File is not executable: {proxy_bin_path}"


def test_start_stack_script():
    """Verify start_stack.sh is executable."""
    script_path = os.path.join(BASE_DIR, "scripts", "start_stack.sh")
    assert os.path.isfile(script_path), f"Script missing: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"


def test_test_request_log():
    """Verify test_request.log contains the expected output from the proxy."""
    log_path = os.path.join(BASE_DIR, "logs", "test_request.log")
    assert os.path.isfile(log_path), f"Log file missing: {log_path}. Did you run the script?"
    with open(log_path, "r") as f:
        assert "DEPLOYMENT_SUCCESS" in f.read(), "Log file does not contain 'DEPLOYMENT_SUCCESS'."


def test_deployment_alert_email():
    """Verify the exact contents of the deployment alert email."""
    email_path = os.path.join(BASE_DIR, "mail", "deployment_alert.eml")
    assert os.path.isfile(email_path), f"Email file missing: {email_path}"

    expected_content = (
        "From: deploybot@localhost\n"
        "To: sysadmin@localhost\n"
        "Subject: Deployment Status\n"
        "\n"
        "Proxy server is running on port 8080.\n"
        "Backend container is on port 9090.\n"
        "Log output captured.\n"
    )

    with open(email_path, "r") as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_content.strip(), "Email content does not match exactly."


def exercise_proxy(binary):
    request = ("request-" + os.urandom(16).hex()).encode()
    response = ("response-" + hashlib.sha256(request).hexdigest()).encode()
    received = []
    ready = threading.Event()
    backend_error = []

    def backend():
        server = None
        conn = None
        try:
            server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            server.bind(("127.0.0.1", 9090))
            server.listen(1)
            server.settimeout(8)
            ready.set()
            conn, _ = server.accept()
            conn.settimeout(5)
            received.append(conn.recv(1024))
            conn.sendall(response)
        except Exception as exc:
            backend_error.append(exc)
            ready.set()
        finally:
            if conn is not None:
                conn.close()
            if server is not None:
                server.close()

    thread = threading.Thread(target=backend, daemon=True)
    thread.start()
    assert ready.wait(3), "Backend failed to start"
    assert not backend_error, f"Backend failed to bind port 9090: {backend_error}"

    proc = subprocess.Popen([binary], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    client.settimeout(5)
    try:
        deadline = time.time() + 5
        while True:
            try:
                client.connect(("127.0.0.1", 8080))
                break
            except (ConnectionRefusedError, OSError):
                if time.time() >= deadline:
                    raise AssertionError("Proxy did not listen on 127.0.0.1:8080")
                time.sleep(0.05)
        client.sendall(request)
        client.shutdown(socket.SHUT_WR)
        actual = b""
        while len(actual) < len(response):
            chunk = client.recv(1024)
            if not chunk:
                break
            actual += chunk
    finally:
        client.close()

    thread.join(6)
    assert not thread.is_alive(), "Proxy did not connect to the backend on port 9090"
    assert not backend_error, f"Backend interaction failed: {backend_error}"
    assert received == [request], "Proxy did not forward the client's bytes to port 9090"
    assert actual == response, "Proxy did not forward the backend response to the client"
    try:
        rc = proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
        raise AssertionError("Proxy did not terminate after handling one request")
    stderr = proc.stderr.read().decode(errors="replace")
    assert rc == 0, f"Proxy did not exit cleanly (status {rc}): {stderr}"


def test_proxy_source_compiles_and_both_artifacts_work():
    source = os.path.join(BASE_DIR, "src", "proxy.c")
    submitted = os.path.join(BASE_DIR, "bin", "proxy_server")
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "proxy_server")
        result = subprocess.run(
            ["gcc", source, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"proxy.c does not compile with gcc: {result.stderr}"
        exercise_proxy(rebuilt)
        exercise_proxy(submitted)


def test_start_stack_contents_and_real_execution():
    script = os.path.join(BASE_DIR, "scripts", "start_stack.sh")
    syntax = subprocess.run(["bash", "-n", script], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert syntax.returncode == 0, f"start_stack.sh has invalid shell syntax: {syntax.stderr}"

    text = open(script, "r").read()
    assert re.search(r'\bcp\b', text) and "/home/user/app_deployment/storage" in text and "/home/user/app_deployment/container_data" in text, "Script must copy storage contents to container_data"
    assert "http.server" in text and "9090" in text and "/home/user/app_deployment/container_data" in text, "Script must start the Python HTTP server on port 9090 for container_data"
    assert "/home/user/app_deployment/bin/proxy_server" in text, "Script must start the compiled proxy_server"
    assert re.search(r'\bsleep\s+2(?:s)?\b', text), "Script must wait 2 seconds for services"
    assert "curl" in text and "http://127.0.0.1:8080/index.html" in text and "/home/user/app_deployment/logs/test_request.log" in text, "Script must curl the proxied index into test_request.log"

    storage_index = os.path.join(BASE_DIR, "storage", "index.html")
    container_index = os.path.join(BASE_DIR, "container_data", "index.html")
    log_path = os.path.join(BASE_DIR, "logs", "test_request.log")
    original_storage = open(storage_index, "rb").read()
    old_container = open(container_index, "rb").read() if os.path.isfile(container_index) else None
    old_log = open(log_path, "rb").read() if os.path.isfile(log_path) else None
    nonce = ("STACK_" + os.urandom(20).hex()).encode()
    proc = None
    try:
        with open(storage_index, "wb") as f:
            f.write(nonce)
        for path in (container_index, log_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        proc = subprocess.Popen(
            [script],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        try:
            rc = proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            raise AssertionError("start_stack.sh did not finish its test request in time")
        assert rc == 0, f"start_stack.sh exited with status {rc}"
        assert os.path.isfile(container_index), "The script did not copy index.html into container_data"
        assert open(container_index, "rb").read().strip() == nonce, "The script did not copy current storage contents"
        assert os.path.isfile(log_path), "The script did not generate test_request.log"
        assert open(log_path, "rb").read().strip() == nonce, "The script's curl did not retrieve the current content through the stack"
    finally:
        if proc is not None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        with open(storage_index, "wb") as f:
            f.write(original_storage)
        if old_container is None:
            try:
                os.remove(container_index)
            except FileNotFoundError:
                pass
        else:
            with open(container_index, "wb") as f:
                f.write(old_container)
        if old_log is None:
            try:
                os.remove(log_path)
            except FileNotFoundError:
                pass
        else:
            with open(log_path, "wb") as f:
                f.write(old_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
