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
import hashlib
import os
import re
import signal
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

import pytest
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

BASE_DIR = "/app/compliance_system"
CERT_DIR = os.path.join(BASE_DIR, "certs")


def run(cmd, **kwargs):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)


def pem_certificates(data):
    if isinstance(data, bytes):
        data = data.decode("ascii", "replace")
    return re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", data, re.S)


def cert_der(pem):
    result = run(["openssl", "x509", "-outform", "DER"], input=pem.encode(), timeout=5)
    assert result.returncode == 0, result.stderr.decode()
    return result.stdout


def cert_fingerprint(pem):
    return hashlib.sha256(cert_der(pem)).hexdigest()


def read_pem(path):
    return Path(path).read_text()


def der_tlv(data, offset):
    start = offset
    tag = data[offset]
    offset += 1
    first = data[offset]
    offset += 1
    if first & 0x80:
        count = first & 0x7f
        assert 0 < count <= 4
        length = int.from_bytes(data[offset:offset + count], "big")
        offset += count
    else:
        length = first
    value_start = offset
    end = value_start + length
    assert end <= len(data)
    return tag, start, value_start, end


def verify_certificate_signature(cert_pem, issuer_pem):
    der = cert_der(cert_pem)
    tag, _, outer_value, outer_end = der_tlv(der, 0)
    assert tag == 0x30 and outer_end == len(der)
    tag, tbs_start, _, tbs_end = der_tlv(der, outer_value)
    assert tag == 0x30
    tag, _, _, algorithm_end = der_tlv(der, tbs_end)
    assert tag == 0x30
    tag, _, signature_value, signature_end = der_tlv(der, algorithm_end)
    assert tag == 0x03 and signature_end == outer_end
    assert der[signature_value] == 0
    signature = der[signature_value + 1:signature_end]

    with tempfile.TemporaryDirectory() as td:
        tbs_path = os.path.join(td, "tbs.der")
        sig_path = os.path.join(td, "sig.bin")
        issuer_path = os.path.join(td, "issuer.pem")
        pub_path = os.path.join(td, "issuer-pub.pem")
        Path(tbs_path).write_bytes(der[tbs_start:tbs_end])
        Path(sig_path).write_bytes(signature)
        Path(issuer_path).write_text(issuer_pem)
        pub = run(["openssl", "x509", "-in", issuer_path, "-pubkey", "-noout"], timeout=5)
        assert pub.returncode == 0, pub.stderr.decode()
        Path(pub_path).write_bytes(pub.stdout)
        checked = run([
            "openssl", "dgst", "-sha256", "-verify", pub_path,
            "-signature", sig_path, tbs_path
        ], timeout=5)
        assert checked.returncode == 0, checked.stderr.decode()
        assert b"Verified OK" in checked.stdout


def listener_inodes(address, port):
    wanted_ip = "0100007F" if address == "127.0.0.1" else None
    wanted_port = f"{port:04X}"
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local, state, inode = fields[1], fields[3], fields[9]
            ip_hex, port_hex = local.split(":")
            if state != "0A" or port_hex.upper() != wanted_port:
                continue
            if wanted_ip is not None and table.endswith("tcp") and ip_hex.upper() != wanted_ip:
                continue
            found.add(inode)
    return found


def listener_pids(address, port):
    inodes = listener_inodes(address, port)
    result = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    result.add(int(proc.name))
                    break
        except (OSError, PermissionError):
            continue
    return result


def executable(pid):
    return os.path.realpath(f"/proc/{pid}/exe")


def stop_backends_and_require_proxy_failure(pids, url):
    stopped = []
    try:
        for pid in pids:
            os.kill(pid, signal.SIGSTOP)
            stopped.append(pid)
        time.sleep(0.15)
        try:
            response = requests.get(url, verify=False, allow_redirects=False, timeout=1)
            assert response.status_code >= 500, (
                f"{url} still returned a fabricated successful response while its backend was stopped"
            )
        except requests.exceptions.RequestException:
            pass
    finally:
        for pid in stopped:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass
        time.sleep(0.15)


def test_server_crt_created():
    """Verify that server.crt is the real leaf plus intermediate full chain."""
    server_crt_path = os.path.join(CERT_DIR, "server.crt")
    assert os.path.isfile(server_crt_path), f"Certificate file {server_crt_path} is missing."
    content = read_pem(server_crt_path)

    # Retain the original full-chain assertion.
    cert_count = content.count("-----BEGIN CERTIFICATE-----")
    assert cert_count >= 2, f"Expected at least 2 certificates in {server_crt_path} for a full chain, found {cert_count}."

    chain = pem_certificates(content)
    leaf = read_pem(os.path.join(CERT_DIR, "leaf.crt"))
    intermediate = read_pem(os.path.join(CERT_DIR, "intermediate.crt"))
    root = read_pem(os.path.join(CERT_DIR, "root.crt"))
    assert cert_fingerprint(chain[0]) == cert_fingerprint(leaf), "server.crt does not begin with leaf.crt"
    assert cert_fingerprint(chain[1]) == cert_fingerprint(intermediate), "server.crt does not contain the provided intermediate as its second certificate"

    # Establish cryptographically that the supplied leaf/intermediate chain leads to the supplied root.
    intermediate_check = run([
        "openssl", "verify", "-CAfile", os.path.join(CERT_DIR, "root.crt"),
        os.path.join(CERT_DIR, "intermediate.crt")
    ], timeout=5)
    assert intermediate_check.returncode == 0, intermediate_check.stderr.decode()
    verify_certificate_signature(leaf, intermediate)
    verify_certificate_signature(intermediate, root)

    leaf_pub = run(["openssl", "x509", "-in", os.path.join(CERT_DIR, "leaf.crt"), "-pubkey", "-noout"], timeout=5)
    key_pub = run(["openssl", "pkey", "-in", os.path.join(CERT_DIR, "server.key"), "-pubout"], timeout=5)
    assert leaf_pub.returncode == 0 and key_pub.returncode == 0
    assert leaf_pub.stdout == key_pub.stdout, "server.key does not match leaf.crt"


def test_nginx_tls_chain():
    """Verify that Nginx serves the supplied leaf and intermediate chain."""
    cmd = [
        "openssl", "s_client", "-connect", "127.0.0.1:8443",
        "-servername", "localhost", "-showcerts",
        "-CAfile", os.path.join(CERT_DIR, "root.crt")
    ]
    try:
        result = subprocess.run(cmd, input=b"Q\n", stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        output = result.stdout.decode("utf-8", "replace")
        # Retain the original assertions.
        assert "s:CN" in output or "i:CN" in output, "Failed to retrieve certificate information from Nginx."
        assert "Certificate chain" in output, "Certificate chain not found in openssl output."

        served = pem_certificates(output)
        assert len(served) >= 2, "Nginx did not serve a leaf and intermediate certificate"
        assert cert_fingerprint(served[0]) == cert_fingerprint(read_pem(os.path.join(CERT_DIR, "leaf.crt")))
        assert cert_fingerprint(served[1]) == cert_fingerprint(read_pem(os.path.join(CERT_DIR, "intermediate.crt")))
    except subprocess.TimeoutExpired:
        pytest.fail("Timeout while trying to connect to Nginx via openssl s_client.")


def test_open_redirect_mitigation():
    url = "https://127.0.0.1:8443/login?redirect_to=http://attacker.com"
    try:
        response = requests.get(url, verify=False, allow_redirects=False, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx at {url}: {e}")
    assert response.status_code == 302, f"Expected HTTP 302 for {url}, got {response.status_code}."
    assert response.headers.get("Location") == "/dashboard", f"Expected redirect to /dashboard, got {response.headers.get('Location')}."


def test_legitimate_redirect():
    url = "https://127.0.0.1:8443/login?redirect_to=/settings"
    try:
        response = requests.get(url, verify=False, allow_redirects=False, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx at {url}: {e}")
    assert response.status_code == 302, f"Expected HTTP 302 for {url}, got {response.status_code}."
    assert response.headers.get("Location") == "/settings", f"Expected redirect to /settings, got {response.headers.get('Location')}."


def test_report_service_integration():
    url = "https://127.0.0.1:8443/audit"
    try:
        response = requests.get(url, verify=False, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx at {url}: {e}")
    assert response.status_code == 200, f"Expected HTTP 200 for {url}, got {response.status_code}."
    assert "Audit Trail Active" in response.text, f"Expected 'Audit Trail Active' in response body, got: {response.text}"


def test_real_services_are_running_and_proxying():
    auth_path = os.path.realpath(os.path.join(BASE_DIR, "auth", "auth-svc"))
    report_path = os.path.realpath(os.path.join(BASE_DIR, "report", "report-bin"))
    assert os.path.isfile(auth_path) and os.access(auth_path, os.X_OK)
    assert os.path.isfile(report_path) and os.access(report_path, os.X_OK)

    auth_pids = listener_pids("127.0.0.1", 8081)
    report_pids = listener_pids("127.0.0.1", 9092)
    tls_pids = listener_pids("127.0.0.1", 8443)
    assert auth_pids, "No process is listening on the Auth service port"
    assert report_pids, "No process is listening on the Report service port"
    assert tls_pids, "No process is listening on the Nginx TLS port"
    assert all(executable(pid) == auth_path for pid in auth_pids), "Port 8081 is not owned by auth/auth-svc"
    assert all(executable(pid) == report_path for pid in report_pids), "Port 9092 is not owned by report/report-bin"
    assert any(os.path.basename(executable(pid)) == "nginx" for pid in tls_pids), "Port 8443 is not owned by Nginx"

    nginx_processes = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if os.path.basename(executable(int(proc.name))) == "nginx":
                cmdline = (proc / "cmdline").read_bytes().replace(b"\0", b" ").decode("utf-8", "replace")
                nginx_processes.append(cmdline)
        except OSError:
            pass
    assert any(os.path.join(BASE_DIR, "nginx.conf") in cmd for cmd in nginx_processes), "Nginx was not started with the required configuration"
    config_check = run(["nginx", "-t", "-c", os.path.join(BASE_DIR, "nginx.conf")], timeout=5)
    assert config_check.returncode == 0, config_check.stderr.decode()

    # Ensure the modified source still builds, rather than accepting an unrelated listener.
    with tempfile.TemporaryDirectory() as td:
        built = run([
            "go", "build", "-o", os.path.join(td, "auth-svc"),
            os.path.join(BASE_DIR, "auth", "main.go")
        ], cwd=os.path.join(BASE_DIR, "auth"), timeout=30)
        assert built.returncode == 0, built.stderr.decode()

    token = uuid.uuid4().hex
    malicious_values = [f"http://{token}.invalid/path", f"https://{token}.invalid/path", f"//{token}.invalid/path"]
    for value in malicious_values:
        direct = requests.get("http://127.0.0.1:8081/login", params={"redirect_to": value}, allow_redirects=False, timeout=3)
        proxied = requests.get("https://127.0.0.1:8443/login", params={"redirect_to": value}, verify=False, allow_redirects=False, timeout=3)
        assert direct.status_code == proxied.status_code == 302
        assert direct.headers.get("Location") == proxied.headers.get("Location") == "/dashboard"

    relative = f"/settings/{token}"
    direct = requests.get("http://127.0.0.1:8081/login", params={"redirect_to": relative}, allow_redirects=False, timeout=3)
    proxied = requests.get("https://127.0.0.1:8443/login", params={"redirect_to": relative}, verify=False, allow_redirects=False, timeout=3)
    assert direct.status_code == proxied.status_code == 302
    assert direct.headers.get("Location") == proxied.headers.get("Location") == relative

    direct_audit = requests.get("http://127.0.0.1:9092/audit", timeout=3)
    proxied_audit = requests.get("https://127.0.0.1:8443/audit", verify=False, timeout=3)
    assert direct_audit.status_code == proxied_audit.status_code == 200
    assert direct_audit.json() == proxied_audit.json()
    assert direct_audit.json().get("status") == "Audit Trail Active"

    # Successful front-end responses must actually depend on each separate backend.
    stop_backends_and_require_proxy_failure(auth_pids, f"https://127.0.0.1:8443/login?redirect_to=/{token}")
    stop_backends_and_require_proxy_failure(report_pids, "https://127.0.0.1:8443/audit")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
