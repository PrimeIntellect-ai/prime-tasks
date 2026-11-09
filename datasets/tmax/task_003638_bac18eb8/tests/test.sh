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
import json
import os
import secrets
import signal
import stat
import subprocess
import tempfile
import time
import zlib

import pytest
import requests

TOKEN = "8A4F-99B2-C7E1-XYZ9"
NGINX_URL = "http://127.0.0.1:8000/upload"
C_SERVER_URL = "http://127.0.0.1:8080/upload"
ARTIFACT_SOURCE = "/home/user/artifact_server.c"
ARTIFACT_BINARY = "/home/user/artifact_server"
UPLOAD_SCRIPT = "/home/user/upload_artifact.sh"


def expected_body(payload):
    checksum = f"{zlib.crc32(payload) & 0xFFFFFFFF:08x}"
    return checksum, f'{{"status": "success", "checksum": "{checksum}"}}'


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_address = fields[1]
                    state = fields[3]
                    if state != "0A":
                        continue
                    if int(local_address.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.scandir("/proc"):
        if not entry.name.isdigit():
            continue
        fd_dir = f"/proc/{entry.name}/fd"
        try:
            for fd in os.scandir(fd_dir):
                try:
                    target = os.readlink(fd.path)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry.name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return pids


def assert_success_response(response, payload):
    checksum, body = expected_body(payload)
    assert response.status_code == 200, (
        f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    )
    assert "application/json" in response.headers.get("Content-Type", ""), (
        "Expected Content-Type: application/json"
    )
    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response body is not valid JSON: {response.text}")
    assert data.get("status") == "success", (
        f"Expected status 'success', got {data.get('status')}"
    )
    assert data.get("checksum") == checksum, (
        f"Expected checksum '{checksum}', got {data.get('checksum')}"
    )
    assert response.text == body, f"Response body is not the exact required JSON: {response.text!r}"


def test_required_artifacts_and_listener_programs():
    assert os.path.isfile(ARTIFACT_SOURCE), f"Missing C source: {ARTIFACT_SOURCE}"
    assert os.path.isfile(ARTIFACT_BINARY), f"Missing compiled server: {ARTIFACT_BINARY}"
    assert os.access(ARTIFACT_BINARY, os.X_OK), f"{ARTIFACT_BINARY} is not executable"
    with open(ARTIFACT_BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{ARTIFACT_BINARY} is not a compiled ELF program"

    server_pids = listener_pids(8080)
    assert server_pids, "No process is listening on port 8080"
    binary_stat = os.stat(ARTIFACT_BINARY)
    for pid in server_pids:
        proc_stat = os.stat(f"/proc/{pid}/exe")
        assert (proc_stat.st_dev, proc_stat.st_ino) == (binary_stat.st_dev, binary_stat.st_ino), (
            f"Port 8080 is held by PID {pid}, not the compiled /home/user/artifact_server"
        )

    nginx_pids = listener_pids(8000)
    assert nginx_pids, "No process is listening on port 8000"
    for pid in nginx_pids:
        exe = os.path.realpath(f"/proc/{pid}/exe")
        assert exe == "/usr/sbin/nginx", f"Port 8000 is held by {exe}, not Nginx"


def test_nginx_rejects_non_post():
    """Test that Nginx rejects GET requests with 405 Method Not Allowed."""
    try:
        response = requests.get(NGINX_URL, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx at {NGINX_URL}: {e}")
    assert response.status_code == 405, f"Expected HTTP 405 for GET request, got {response.status_code}"


def test_nginx_intercepts_non_post_before_c_server():
    server_pids = listener_pids(8080)
    assert server_pids, "No C server listener found"
    stopped = []
    try:
        for pid in server_pids:
            os.kill(pid, signal.SIGSTOP)
            stopped.append(pid)
        time.sleep(0.1)
        response = requests.get(NGINX_URL, timeout=2)
        assert response.status_code == 405, (
            "Nginx did not independently reject GET while the upstream server was stopped"
        )
    except requests.RequestException as e:
        pytest.fail(f"Nginx appears to have forwarded GET to the stopped upstream: {e}")
    finally:
        for pid in stopped:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass


def test_unauthorized_post_rejected():
    """Test that POST requests without the correct Auth header are rejected with 401."""
    try:
        response = requests.post(NGINX_URL, data=b"HelloWorld", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx at {NGINX_URL}: {e}")
    assert response.status_code == 401, f"Expected HTTP 401 for missing Auth header, got {response.status_code}"

    wrong = {"Authorization": "Bearer " + secrets.token_hex(12)}
    assert requests.post(NGINX_URL, data=secrets.token_bytes(31), headers=wrong, timeout=5).status_code == 401
    assert requests.post(C_SERVER_URL, data=secrets.token_bytes(29), headers=wrong, timeout=5).status_code == 401


def test_successful_post_crc32():
    """Test that a valid POST request returns 200 and the correct CRC32 checksum."""
    payload = b"HelloWorld"
    headers = {"Authorization": f"Bearer {TOKEN}"}
    try:
        response = requests.post(NGINX_URL, data=payload, headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx at {NGINX_URL}: {e}")
    assert_success_response(response, payload)


def test_c_server_directly():
    """Test the C server directly to ensure it is running on port 8080."""
    payload = b"DirectTest"
    expected_crc32 = f"{zlib.crc32(payload) & 0xFFFFFFFF:08x}"
    headers = {"Authorization": f"Bearer {TOKEN}"}
    try:
        response = requests.post(C_SERVER_URL, data=payload, headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to C server at {C_SERVER_URL}: {e}")
    assert response.status_code == 200, f"Expected HTTP 200 from C server, got {response.status_code}"
    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"C server response body is not valid JSON: {response.text}")
    assert data.get("checksum") == expected_crc32, (
        f"Expected checksum '{expected_crc32}' from C server, got {data.get('checksum')}"
    )


def test_crc32_on_unpredictable_binary_payloads():
    headers = {"Authorization": f"Bearer {TOKEN}"}
    for size in (73, 521, 4093):
        payload = secrets.token_bytes(size)
        direct = requests.post(C_SERVER_URL, data=payload, headers=headers, timeout=5)
        proxied = requests.post(NGINX_URL, data=payload, headers=headers, timeout=5)
        assert_success_response(direct, payload)
        assert_success_response(proxied, payload)


def test_only_upload_endpoint_is_exposed():
    headers = {"Authorization": f"Bearer {TOKEN}"}
    payload = secrets.token_bytes(47)
    for base in ("http://127.0.0.1:8080", "http://127.0.0.1:8000"):
        response = requests.post(base + "/not-upload", data=payload, headers=headers, timeout=5)
        assert response.status_code != 200, f"Unexpected successful endpoint at {base}/not-upload"


def test_upload_script_exists_and_executable():
    """Test that the upload script exists, is executable, and contains the required elements."""
    assert os.path.exists(UPLOAD_SCRIPT), f"Script {UPLOAD_SCRIPT} does not exist"
    assert os.path.isfile(UPLOAD_SCRIPT), f"{UPLOAD_SCRIPT} is not a file"
    assert os.access(UPLOAD_SCRIPT, os.X_OK), f"Script {UPLOAD_SCRIPT} is not executable"
    with open(UPLOAD_SCRIPT) as f:
        content = f.read()
    assert "curl" in content, "Script does not use curl"
    assert "127.0.0.1:8000/upload" in content or "localhost:8000/upload" in content, (
        "Script does not point to the correct Nginx URL"
    )
    assert TOKEN in content, "Script does not contain the extracted token"


def test_upload_script_is_executed_and_uploads_file():
    payload = secrets.token_bytes(997)
    with tempfile.NamedTemporaryFile() as artifact:
        artifact.write(payload)
        artifact.flush()
        result = subprocess.run(
            [UPLOAD_SCRIPT, artifact.name], capture_output=True, text=True, timeout=10
        )
    assert result.returncode == 0, f"Upload script failed: {result.stderr}"
    checksum, body = expected_body(payload)
    assert result.stdout.strip() == body, (
        f"Upload script did not return the service response for the supplied file: {result.stdout!r}"
    )
    parsed = json.loads(result.stdout)
    assert parsed == {"status": "success", "checksum": checksum}

    no_args = subprocess.run([UPLOAD_SCRIPT], capture_output=True, text=True, timeout=5)
    two_args = subprocess.run(
        [UPLOAD_SCRIPT, "/dev/null", "/dev/null"], capture_output=True, text=True, timeout=5
    )
    assert no_args.returncode != 0, "Upload script must reject zero arguments"
    assert two_args.returncode != 0, "Upload script must reject more than one argument"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
