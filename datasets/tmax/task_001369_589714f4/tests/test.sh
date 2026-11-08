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
import base64
import hashlib
import hmac
import os
import secrets
import shutil
import signal
import string
import subprocess
import tempfile
import time

import pytest
import requests

GATEWAY_URL = "http://127.0.0.1:8080"
AUTH_URL = "http://127.0.0.1:8081"
CSP = "default-src 'self'"
ORIGINAL_SECRET = b"super_secret_hmac_key_123"


def make_token(payload, secret=ORIGINAL_SECRET):
    b64_payload = base64.b64encode(payload)
    digest = hmac.new(secret, b64_payload, hashlib.sha256).hexdigest()
    return f"{b64_payload.decode()}.{digest}"


def assert_csp(response):
    assert response.headers.get("Content-Security-Policy") == CSP, (
        f"Missing or incorrect CSP on {response.request.method} "
        f"{response.request.url} ({response.status_code})"
    )


def test_forge_go_output():
    """Test that /home/user/forge.go generates the correct forged XOR token."""
    forge_path = "/home/user/forge.go"
    assert os.path.isfile(forge_path), f"Forge program missing: {forge_path}"

    try:
        result = subprocess.run(
            ["go", "run", forge_path],
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"go run {forge_path} failed with exit code {e.returncode}. "
            f"stderr: {e.stderr}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"go run {forge_path} timed out.")

    output = result.stdout.strip()
    payload = b"role=admin"
    xored = bytes(b ^ 0x42 for b in payload)
    expected_token = base64.b64encode(xored).decode("utf-8")
    assert output == expected_token, (
        f"Forge program output '{output}' does not match expected '{expected_token}'"
    )


def test_auth_service_is_running_and_issues_weak_tokens():
    """The required Auth Service must actually be listening on port 8081."""
    role = "audit_" + secrets.token_hex(8)
    try:
        response = requests.get(f"{AUTH_URL}/token", params={"role": role}, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to contact Auth Service at {AUTH_URL}/token: {e}")

    assert response.status_code == 200
    payload = ("role=" + role).encode()
    expected = base64.b64encode(bytes(b ^ 0x42 for b in payload)).decode()
    assert response.text == expected


def test_gateway_csp_header():
    """Test that the API Gateway includes the correct CSP header."""
    try:
        response = requests.get(f"{GATEWAY_URL}/", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API Gateway at {GATEWAY_URL}/: {e}")

    csp_header = response.headers.get("Content-Security-Policy")
    assert csp_header is not None, "Content-Security-Policy header is missing from the gateway response."
    assert csp_header == CSP, f"Incorrect CSP header value: {csp_header}"


def test_gateway_rejects_old_token():
    """Test that the API Gateway rejects the old XOR token."""
    payload = b"role=admin"
    xored = bytes(b ^ 0x42 for b in payload)
    old_token = base64.b64encode(xored).decode("utf-8")
    headers = {"Authorization": f"Bearer {old_token}"}

    try:
        response = requests.get(f"{GATEWAY_URL}/admin", headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API Gateway at {GATEWAY_URL}/admin: {e}")

    assert response.status_code == 401, (
        f"Expected HTTP 401 Unauthorized for old token, got {response.status_code}"
    )


def test_gateway_accepts_new_token():
    """Test that the API Gateway accepts the new HMAC-SHA256 token."""
    new_token = make_token(b"role=admin")
    headers = {"Authorization": f"Bearer {new_token}"}

    try:
        response = requests.get(f"{GATEWAY_URL}/admin", headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API Gateway at {GATEWAY_URL}/admin: {e}")

    assert response.status_code == 200, (
        f"Expected HTTP 200 OK for valid HMAC token, got {response.status_code}. "
        f"Response: {response.text}"
    )


def test_csp_is_present_on_all_gateway_response_classes():
    valid = make_token(b"role=admin")
    invalid_sig = secrets.token_hex(32)
    cases = [
        requests.get(f"{GATEWAY_URL}/", timeout=5),
        requests.get(f"{GATEWAY_URL}/path-{secrets.token_hex(6)}", timeout=5),
        requests.get(f"{GATEWAY_URL}/admin", timeout=5),
        requests.get(
            f"{GATEWAY_URL}/admin",
            headers={"Authorization": f"Bearer cm9sZT1hZG1pbg==.{invalid_sig}"},
            timeout=5,
        ),
        requests.get(
            f"{GATEWAY_URL}/admin",
            headers={"Authorization": f"Bearer {valid}"},
            timeout=5,
        ),
        requests.post(f"{GATEWAY_URL}/admin", timeout=5),
    ]
    for response in cases:
        assert_csp(response)


def _kill_listener(port):
    """Terminate the process owning a listening TCP socket on the given port."""
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9:
                        local = fields[1]
                        state = fields[3]
                        if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
        except (FileNotFoundError, PermissionError):
            continue

    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_built_gateway_performs_real_hmac_validation_with_csp():
    """Re-key the built artifact unpredictably and exercise derived valid/invalid tokens."""
    source_dir = "/app/gateway"
    assert os.path.isfile(os.path.join(source_dir, "main.go"))

    temp_dir = tempfile.mkdtemp(prefix="gateway-audit-")
    binary = os.path.join(temp_dir, "gateway")
    process = None
    try:
        env = os.environ.copy()
        env.setdefault("GO111MODULE", "off")
        build = subprocess.run(
            ["go", "build", "-o", binary, "."],
            cwd=source_dir,
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, f"Gateway does not compile: {build.stderr}"

        alphabet = string.ascii_letters + string.digits
        random_secret = "".join(secrets.choice(alphabet) for _ in range(len(ORIGINAL_SECRET))).encode()
        assert random_secret != ORIGINAL_SECRET

        with open(binary, "rb") as f:
            image = f.read()
        occurrences = image.count(ORIGINAL_SECRET)
        assert occurrences > 0, "Built gateway does not contain the required static HMAC key"
        image = image.replace(ORIGINAL_SECRET, random_secret)
        with open(binary, "wb") as f:
            f.write(image)
        os.chmod(binary, 0o755)

        _kill_listener(8080)
        process = subprocess.Popen(binary, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        deadline = time.time() + 8
        while time.time() < deadline:
            if process.poll() is not None:
                out, err = process.communicate(timeout=1)
                pytest.fail(f"Re-keyed gateway exited early: {err.decode(errors='replace')}")
            try:
                requests.get(GATEWAY_URL + "/", timeout=0.3)
                break
            except requests.exceptions.RequestException:
                time.sleep(0.1)
        else:
            pytest.fail("Re-keyed gateway did not start on 127.0.0.1:8080")

        valid_admin = make_token(b"role=admin", random_secret)
        valid_user = make_token(b"role=user", random_secret)
        old_key_admin = make_token(b"role=admin", ORIGINAL_SECRET)
        old_xor = base64.b64encode(bytes(b ^ 0x42 for b in b"role=admin")).decode()
        random_bad_mac = secrets.token_hex(32)

        responses = [
            (requests.get(GATEWAY_URL + "/admin", headers={"Authorization": f"Bearer {valid_admin}"}, timeout=3), 200),
            (requests.get(GATEWAY_URL + "/admin", headers={"Authorization": f"Bearer {valid_user}"}, timeout=3), 401),
            (requests.get(GATEWAY_URL + "/admin", headers={"Authorization": f"Bearer {old_key_admin}"}, timeout=3), 401),
            (requests.get(GATEWAY_URL + "/admin", headers={"Authorization": f"Bearer {old_xor}"}, timeout=3), 401),
            (requests.get(GATEWAY_URL + "/admin", headers={"Authorization": f"Bearer cm9sZT1hZG1pbg==.{random_bad_mac}"}, timeout=3), 401),
            (requests.get(GATEWAY_URL + "/admin", headers={"Authorization": "Bearer malformed.token"}, timeout=3), 401),
            (requests.get(GATEWAY_URL + "/admin", timeout=3), 401),
            (requests.get(GATEWAY_URL + "/", timeout=3), 200),
        ]
        for response, expected_status in responses:
            assert response.status_code == expected_status, (
                f"Expected {expected_status}, got {response.status_code}: {response.text}"
            )
            assert_csp(response)
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
        shutil.rmtree(temp_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
