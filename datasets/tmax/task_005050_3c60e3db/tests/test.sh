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
import datetime
import os
import re
import secrets
import socket
import ssl
import stat
import subprocess
from pathlib import Path

import pytest
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

BASE_URL = "https://127.0.0.1:8443"
CERT_PATH = "/app/certs/server.crt"
KEY_PATH = "/app/certs/server.key"
SERVER_PATH = "/app/server.py"
PID_PATH = "/app/server.pid"
EXPECTED_ATTACKER_DOMAIN = "evil-exfil-server.xyz"


def run_checked(command, input_data=None):
    result = subprocess.run(
        command,
        input=input_data,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"Command failed: {' '.join(command)}\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return result.stdout


def request_next(value):
    try:
        return requests.get(
            f"{BASE_URL}/login",
            params={"next": value},
            verify=False,
            allow_redirects=False,
            timeout=5,
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Request with next={value!r} failed: {exc}")


def read_pid():
    assert os.path.exists(PID_PATH), f"PID file not found at {PID_PATH}"
    pid_str = Path(PID_PATH).read_text().strip()
    assert pid_str.isdigit(), f"PID file contains invalid PID: {pid_str}"
    return int(pid_str)


def extract_attacker_domain():
    result = subprocess.run(
        ["tesseract", "/app/evidence.png", "stdout"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"OCR failed: {result.stderr}"
    match = re.search(r"ATTACKER_DOMAIN\s*:\s*([A-Za-z0-9.-]+)", result.stdout)
    assert match, f"Could not extract attacker domain from OCR output: {result.stdout!r}"
    domain = match.group(1).rstrip(".")
    assert domain == EXPECTED_ATTACKER_DOMAIN, (
        f"Unexpected attacker domain extracted from evidence: {domain}"
    )
    return domain


def test_key_permissions():
    assert os.path.exists(KEY_PATH), f"Private key not found at {KEY_PATH}"
    permissions = stat.S_IMODE(os.stat(KEY_PATH).st_mode)
    assert permissions == 0o600, (
        f"Expected permissions 600 for {KEY_PATH}, got {oct(permissions)}"
    )


def test_certificate_subject():
    assert os.path.exists(CERT_PATH), f"Certificate not found at {CERT_PATH}"
    result = subprocess.run(
        ["openssl", "x509", "-in", CERT_PATH, "-noout", "-subject"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, "Failed to read certificate subject using openssl."
    assert "CN = localhost" in result.stdout or "CN=localhost" in result.stdout, (
        f"Expected CN=localhost in certificate subject, got: {result.stdout}"
    )


def test_certificate_key_size_validity_and_pairing():
    cert_pub = run_checked(["openssl", "x509", "-in", CERT_PATH, "-pubkey", "-noout"])
    key_pub = run_checked(["openssl", "pkey", "-in", KEY_PATH, "-pubout"])
    assert cert_pub.strip() == key_pub.strip(), "Certificate and private key do not pair"

    key_details = run_checked(
        ["openssl", "pkey", "-pubin", "-text", "-noout"],
        input_data=cert_pub,
    )
    assert re.search(r"Public-Key:\s*\(2048 bit\)", key_details), (
        f"Certificate does not use an RSA-2048 public key: {key_details}"
    )
    assert "Modulus:" in key_details and "Exponent:" in key_details, (
        "Certificate public key is not RSA"
    )

    dates = run_checked(
        ["openssl", "x509", "-in", CERT_PATH, "-noout", "-startdate", "-enddate"]
    )
    values = dict(line.strip().split("=", 1) for line in dates.splitlines() if "=" in line)
    date_format = "%b %d %H:%M:%S %Y %Z"
    not_before = datetime.datetime.strptime(values["notBefore"], date_format).replace(
        tzinfo=datetime.timezone.utc
    )
    not_after = datetime.datetime.strptime(values["notAfter"], date_format).replace(
        tzinfo=datetime.timezone.utc
    )
    lifetime = not_after - not_before
    assert abs(lifetime.total_seconds() - 365 * 24 * 60 * 60) <= 60, (
        f"Expected a 365-day certificate, got lifetime {lifetime}"
    )
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now <= not_after, "Certificate is not currently valid"


def test_server_implementation_exists_and_compiles():
    assert os.path.isfile(SERVER_PATH), f"Server implementation not found at {SERVER_PATH}"
    assert not os.path.islink(SERVER_PATH), f"{SERVER_PATH} must be a regular implementation file"
    assert os.path.getsize(SERVER_PATH) > 0, f"{SERVER_PATH} is empty"
    result = subprocess.run(
        ["python3", "-m", "py_compile", SERVER_PATH],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Server implementation is not valid Python: {result.stderr}"


def test_server_pid_file():
    pid = read_pid()
    proc_dir = Path(f"/proc/{pid}")
    assert proc_dir.exists(), f"PID {pid} from {PID_PATH} is not running"

    cmdline = (proc_dir / "cmdline").read_bytes().split(b"\0")
    cwd = os.readlink(proc_dir / "cwd")
    resolved_args = set()
    for raw_arg in cmdline:
        if not raw_arg:
            continue
        arg = os.fsdecode(raw_arg)
        if arg.endswith(".py"):
            resolved_args.add(os.path.realpath(arg if os.path.isabs(arg) else os.path.join(cwd, arg)))
    assert os.path.realpath(SERVER_PATH) in resolved_args, (
        f"PID {pid} is not executing {SERVER_PATH}; cmdline was {cmdline!r}"
    )

    socket_inodes = set()
    for fd in (proc_dir / "fd").iterdir():
        try:
            target = os.readlink(fd)
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            socket_inodes.add(match.group(1))

    owns_expected_listener = False
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(table):
            continue
        for line in Path(table).read_text().splitlines()[1:]:
            fields = line.split()
            local_address, state, inode = fields[1], fields[3], fields[9]
            if table.endswith("tcp"):
                expected_address = "0100007F:20FB"
            else:
                expected_address = "0000000000000000FFFF00000100007F:20FB"
            if local_address.upper() == expected_address and state == "0A" and inode in socket_inodes:
                owns_expected_listener = True
    assert owns_expected_listener, (
        f"PID {pid} does not own the HTTPS listener on 127.0.0.1:8443"
    )


def test_live_server_uses_submitted_certificate():
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    with socket.create_connection(("127.0.0.1", 8443), timeout=5) as raw_socket:
        with context.wrap_socket(raw_socket, server_hostname="localhost") as tls_socket:
            live_der = tls_socket.getpeercert(binary_form=True)

    pem = Path(CERT_PATH).read_text()
    submitted_der = ssl.PEM_cert_to_DER_cert(pem)
    if isinstance(submitted_der, str):
        submitted_der = base64.b64decode(submitted_der)
    assert live_der == submitted_der, "Running server is not using /app/certs/server.crt"


def test_valid_redirect():
    url = f"{BASE_URL}/login?next=/profile"
    try:
        response = requests.get(url, verify=False, allow_redirects=False, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Request to {url} failed: {exc}")
    assert response.status_code == 302, (
        f"Expected 302 Found, got {response.status_code}. Response: {response.text}"
    )
    assert response.headers.get("Location") == "/profile", (
        f"Expected Location: /profile, got {response.headers.get('Location')}"
    )


def test_open_redirect_generic():
    response = request_next("https://google.com")
    assert response.status_code == 400, (
        f"Expected 400 Bad Request, got {response.status_code}. Response: {response.text}"
    )
    assert "Invalid Redirect" in response.text


def test_open_redirect_protocol_relative():
    response = request_next("//google.com")
    assert response.status_code == 400, (
        f"Expected 400 Bad Request, got {response.status_code}. Response: {response.text}"
    )
    assert "Invalid Redirect" in response.text


def test_intrusion_detection():
    response = request_next("http://evil-exfil-server.xyz/steal")
    assert response.status_code == 403, (
        f"Expected 403 Forbidden, got {response.status_code}. Response: {response.text}"
    )
    assert "Intrusion Detected" in response.text


def test_randomized_redirect_rules():
    attacker_domain = extract_attacker_domain()

    for _ in range(4):
        relative = f"/{secrets.token_hex(8)}/{secrets.token_hex(6)}"
        response = request_next(relative)
        assert response.status_code == 302, (
            f"Expected 302 for randomized relative path {relative!r}, got {response.status_code}"
        )
        assert response.headers.get("Location") == relative

    for scheme in ("http://", "https://", "//"):
        external = f"{scheme}{secrets.token_hex(10)}.example/{secrets.token_hex(7)}"
        response = request_next(external)
        assert response.status_code == 400, (
            f"Expected 400 for randomized absolute URL {external!r}, got {response.status_code}"
        )
        assert "Invalid Redirect" in response.text

    attacker_values = [
        f"https://{attacker_domain}/{secrets.token_hex(8)}",
        f"/{secrets.token_hex(5)}/{attacker_domain}/{secrets.token_hex(5)}",
    ]
    for value in attacker_values:
        response = request_next(value)
        assert response.status_code == 403, (
            f"Expected 403 for value containing attacker domain {value!r}, got {response.status_code}"
        )
        assert "Intrusion Detected" in response.text


def test_only_login_endpoint_is_implemented():
    path = f"/{secrets.token_hex(12)}"
    try:
        response = requests.get(
            BASE_URL + path,
            verify=False,
            allow_redirects=False,
            timeout=5,
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Request to non-login endpoint failed: {exc}")
    assert response.status_code == 404, (
        f"Expected unknown endpoint {path} to return 404, got {response.status_code}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
