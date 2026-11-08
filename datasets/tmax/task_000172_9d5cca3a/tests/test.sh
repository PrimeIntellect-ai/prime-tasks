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
import subprocess
import tempfile
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090"


def wait_for_service():
    for _ in range(10):
        try:
            requests.get(f"{BASE_URL}/", timeout=1)
            return
        except requests.exceptions.RequestException:
            time.sleep(0.5)
    pytest.fail("Service is not running on 127.0.0.1:9090 or not accepting connections.")


def test_makefile_fixed():
    """Ensure the Makefile typo has been fixed and installs only to /usr/local/bin."""
    makefile_path = "/app/bash-conf-tracker/Makefile"
    assert os.path.isfile(makefile_path), "Makefile is missing."
    with open(makefile_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "/user/bin/" not in content, "Makefile still contains the typo '/user/bin/'."
    assert "/usr/local/bin" in content or "/usr/bin" in content, "Makefile does not contain a valid installation path."

    # The instruction specifically requires /usr/local/bin, not /usr/bin.
    assert "/usr/local/bin" in content, "Makefile does not install to /usr/local/bin."
    assert "/usr/bin/" not in content, "Makefile incorrectly permits installation to /usr/bin."

    dry_run = subprocess.run(
        ["make", "-n", "install"],
        cwd="/app/bash-conf-tracker",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert dry_run.returncode == 0, f"Makefile install target is invalid: {dry_run.stderr}"
    assert "/usr/local/bin" in dry_run.stdout, "install target does not copy scripts to /usr/local/bin."
    assert "/user/bin" not in dry_run.stdout and "/usr/bin/" not in dry_run.stdout, "install target uses the wrong directory."


def test_scripts_were_installed():
    """Verify make install's required artifacts are present and match the vendored scripts."""
    for name in ("normalize.sh", "start_server.sh"):
        source = f"/app/bash-conf-tracker/{name}"
        installed = f"/usr/local/bin/{name}"
        assert os.path.isfile(source), f"Vendored {name} is missing."
        assert os.path.isfile(installed), f"{installed} was not installed."
        assert os.access(installed, os.X_OK), f"{installed} is not executable."
        with open(source, "rb") as src, open(installed, "rb") as dst:
            assert src.read() == dst.read(), f"Installed {name} does not match the fixed vendored script."


def test_normalize_sh_fixed():
    """Preserve the source check and behaviorally test arbitrary unterminated input."""
    normalize_path = "/app/bash-conf-tracker/normalize.sh"
    assert os.path.isfile(normalize_path), "normalize.sh is missing."
    with open(normalize_path, "r") as f:
        content = f.read()
    assert "|| [ -n" in content or "|| [[ -n" in content or "|| [ ! -z" in content or "|| [[ ! -z" in content, \
        "The normalize.sh script does not contain the fix for the read loop (e.g., || [ -n \"$line\" ])."

    token = secrets.token_hex(8)
    host = f"norm-{secrets.token_hex(6)}"
    dynamic_key = f"Feature_{secrets.token_hex(4)}"
    payload = (
        f"  {dynamic_key} = \"first-{token}\"  \n"
        f"BUILD = release={token}\n"
        f"{dynamic_key.upper()} = \"last-{token}\"\n"
        f"  HOSTNAME = {host}"
    )
    assert not payload.endswith("\n"), "Behavioral test payload must be unterminated."

    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, "input.txt")
        output_path = os.path.join(td, "output.json")
        with open(input_path, "wb") as f:
            f.write(payload.encode())
        result = subprocess.run(
            ["/usr/local/bin/normalize.sh", input_path, output_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert result.returncode == 0, f"Installed normalizer rejected valid input: {result.stderr.decode(errors='replace')}"
        with open(output_path) as f:
            data = json.load(f)

    expected = {
        dynamic_key.lower(): f"last-{token}",
        "build": f"release={token}",
        "hostname": host,
    }
    assert data == expected, f"Normalizer produced {data!r}, expected {expected!r}."

    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, "missing.txt")
        output_path = os.path.join(td, "missing.json")
        with open(input_path, "w") as f:
            f.write(f"KEY={secrets.token_hex(5)}")
        result = subprocess.run(
            ["/usr/local/bin/normalize.sh", input_path, output_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert result.returncode != 0, "Normalizer accepted input without a hostname."


def test_service_bound_to_required_address():
    wait_for_service()
    port_hex = f"{9090:04X}"
    listeners = []
    with open("/proc/net/tcp") as f:
        next(f)
        for line in f:
            fields = line.split()
            local_address, state = fields[1], fields[3]
            address, port = local_address.split(":")
            if port.upper() == port_hex and state == "0A":
                listeners.append(address.upper())
    assert "0100007F" in listeners, "No service is listening on IPv4 127.0.0.1:9090."
    assert "00000000" not in listeners, "Service is listening on all IPv4 interfaces instead of exactly 127.0.0.1."


def test_service_running_and_processing():
    """Preserve the original functional upload assertions."""
    wait_for_service()
    payload = 'OS=Ubuntu\nVERSION="22.04"\n hostname = db-server-01 \nOS = Debian\nAPP_ENV=production'
    try:
        post_response = requests.post(f"{BASE_URL}/upload", data=payload, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running on 127.0.0.1:9090 or not accepting connections.")

    assert post_response.status_code in (200, 201), f"Expected successful upload, got {post_response.status_code}"
    config_file = "/home/user/configs/db-server-01.json"
    assert os.path.isfile(config_file), f"Config file {config_file} was not created."
    with open(config_file, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Config file does not contain valid JSON.")

    expected_data = {
        "os": "Debian",
        "version": "22.04",
        "hostname": "db-server-01",
        "app_env": "production",
    }
    for k, v in expected_data.items():
        assert data.get(k) == v, f"Expected key '{k}' to be '{v}', got '{data.get(k)}'"


def test_service_get_endpoint():
    """Preserve the original GET endpoint assertions."""
    response = requests.get(f"{BASE_URL}/config?host=db-server-01", timeout=5)
    assert response.status_code == 200, f"Expected GET to return 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("GET response is not valid JSON.")
    assert data.get("hostname") == "db-server-01", "GET response JSON does not contain correct hostname."


def test_service_missing_hostname():
    """Preserve the original missing-hostname assertion."""
    payload = "OS=Ubuntu\nAPP_ENV=production"
    response = requests.post(f"{BASE_URL}/upload", data=payload, timeout=5)
    assert response.status_code == 400, f"Expected POST without hostname to return 400, got {response.status_code}"


def test_randomized_upload_storage_and_get():
    """Exercise arbitrary hosts, keys, values, duplicates, and unterminated payloads."""
    for _ in range(3):
        host = f"host-{secrets.token_hex(8)}"
        key = f"Setting_{secrets.token_hex(5)}"
        first = f"old-{secrets.token_hex(6)}"
        last = f"new-{secrets.token_hex(6)}"
        other = f"value={secrets.token_hex(7)}"
        payload = (
            f"  {key.upper()} = \"{first}\"  \n"
            f"Extra_Field = {other}\n"
            f"{key.lower()}={last}\n"
            f" HOSTNAME = \"{host}\""
        )
        assert not payload.endswith("\n")

        response = requests.post(f"{BASE_URL}/upload", data=payload, timeout=5)
        assert response.status_code in (200, 201), f"Upload for arbitrary host failed with {response.status_code}."

        expected = {
            key.lower(): last,
            "extra_field": other,
            "hostname": host,
        }
        config_file = f"/home/user/configs/{host}.json"
        assert os.path.isfile(config_file), f"Service did not store {config_file}."
        with open(config_file) as f:
            stored = json.load(f)
        assert stored == expected, f"Stored JSON was {stored!r}, expected {expected!r}."

        fetched = requests.get(f"{BASE_URL}/config?host={host}", timeout=5)
        assert fetched.status_code == 200, f"GET for arbitrary host returned {fetched.status_code}."
        try:
            fetched_data = fetched.json()
        except ValueError:
            pytest.fail("GET response for arbitrary host is not valid JSON.")
        assert fetched_data == expected, "GET response does not match the stored normalized configuration."


def test_random_unknown_host_returns_404():
    unknown = f"absent-{secrets.token_hex(12)}"
    assert not os.path.exists(f"/home/user/configs/{unknown}.json")
    response = requests.get(f"{BASE_URL}/config?host={unknown}", timeout=5)
    assert response.status_code == 404, f"Expected unknown host to return 404, got {response.status_code}."


def test_random_missing_hostname_returns_400():
    key = f"KEY_{secrets.token_hex(5)}"
    payload = f"{key}=first\n{key.lower()}=last-{secrets.token_hex(7)}"
    response = requests.post(f"{BASE_URL}/upload", data=payload, timeout=5)
    assert response.status_code == 400, f"Expected arbitrary payload without hostname to return 400, got {response.status_code}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
