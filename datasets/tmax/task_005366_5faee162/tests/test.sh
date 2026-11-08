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
import os
import re
import secrets
import subprocess

import pytest
import requests

SERVICE = "http://127.0.0.1:8080"
CSP = "default-src 'self'"
_auth_cache = None


def _post_upload(filename, content, headers=None, fields=None):
    data = dict(fields or {})
    return requests.post(
        SERVICE + "/upload",
        files={"file": (filename, content)},
        data=data,
        headers=headers or {},
        timeout=3,
        allow_redirects=False,
    )


def _working_auth():
    global _auth_cache
    if _auth_cache is not None:
        return _auth_cache

    good_basic = base64.b64encode(b"admin:butterfly").decode()
    bad_basic = base64.b64encode(b"admin:definitely-wrong").decode()
    candidates = [
        ({"Authorization": "Basic " + good_basic}, {}, {"Authorization": "Basic " + bad_basic}, {}),
        ({"Authorization": "Bearer butterfly"}, {}, {"Authorization": "Bearer definitely-wrong"}, {}),
        ({"X-Auth-Token": "butterfly"}, {}, {"X-Auth-Token": "definitely-wrong"}, {}),
        ({"X-Password": "butterfly"}, {}, {"X-Password": "definitely-wrong"}, {}),
        ({}, {"password": "butterfly"}, {}, {"password": "definitely-wrong"}),
        ({}, {"token": "butterfly"}, {}, {"token": "definitely-wrong"}),
        ({}, {"username": "admin", "password": "butterfly"}, {}, {"username": "admin", "password": "definitely-wrong"}),
    ]

    for good_headers, good_fields, bad_headers, bad_fields in candidates:
        try:
            good = _post_upload("auth-check.txt", b"authenticated upload", good_headers, good_fields)
            bad = _post_upload("auth-check.txt", b"authenticated upload", bad_headers, bad_fields)
        except requests.RequestException:
            continue
        if good.status_code in (200, 201) and bad.status_code in (400, 401, 403):
            _auth_cache = (good_headers, good_fields)
            return _auth_cache

    pytest.fail("The upload service did not accept the cracked password while rejecting an incorrect password")


def test_required_files_exist():
    secure_upload_path = "/home/user/secure_upload.py"
    firewall_script_path = "/home/user/firewall_setup.sh"

    assert os.path.exists(secure_upload_path), f"Missing required file: {secure_upload_path}"
    assert os.path.exists(firewall_script_path), f"Missing required file: {firewall_script_path}"
    assert os.path.isfile(secure_upload_path), "secure_upload.py is not a regular file"
    assert os.path.isfile(firewall_script_path), "firewall_setup.sh is not a regular file"
    assert os.path.getsize(secure_upload_path) > 0, "secure_upload.py is empty"
    assert os.path.getsize(firewall_script_path) > 0, "firewall_setup.sh is empty"

    compile_result = subprocess.run(
        ["python3", "-m", "py_compile", secure_upload_path],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert compile_result.returncode == 0, f"secure_upload.py is not valid Python: {compile_result.stderr}"


def test_incident_report_content():
    report_path = "/home/user/incident_report.log"
    assert os.path.exists(report_path), f"Missing required file: {report_path}"

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, "Incident report does not contain enough lines."
    assert lines[0] == "butterfly", f"Expected first line to be 'butterfly', got '{lines[0]}'"
    assert lines[1] == "1337", f"Expected second line to be '1337', got '{lines[1]}'"


def test_service_is_running_from_required_python_file():
    listener_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(table, "r") as f:
            next(f)
            for line in f:
                parts = line.split()
                local_address = parts[1]
                state = parts[3]
                if int(local_address.rsplit(":", 1)[1], 16) == 8080 and state == "0A":
                    listener_inodes.add(parts[9])

    assert listener_inodes, "No process is listening on TCP port 8080"
    matching_process = False
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        owns_listener = False
        for fd in fds:
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in listener_inodes:
                owns_listener = True
                break
        if not owns_listener:
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            exe = os.path.basename(os.readlink(f"/proc/{pid}/exe")).lower()
        except OSError:
            continue
        if any(os.path.realpath(arg) == "/home/user/secure_upload.py" for arg in argv) and "python" in exe:
            matching_process = True
            break

    assert matching_process, "Port 8080 is not being served by the required secure_upload.py Python service"


def test_service_csp_header():
    url = SERVICE + "/"
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the secure upload service at {url}: {e}")

    csp_header = response.headers.get("Content-Security-Policy")
    assert csp_header is not None, "Content-Security-Policy header is missing from the response."
    assert csp_header == CSP, f"Incorrect CSP header value. Expected \"{CSP}\", got \"{csp_header}\""


def test_service_path_traversal_protection():
    url = SERVICE + "/upload"
    malicious_filename = "../../../etc/passwd"
    files = {"file": (malicious_filename, b"test content")}

    try:
        response = requests.post(url, files=files, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the secure upload service at {url}: {e}")

    assert response.status_code in [200, 201, 400, 403], f"Unexpected status code {response.status_code} when attempting path traversal."
    if response.status_code in [200, 201]:
        assert malicious_filename not in response.text, "Service accepted the upload but appears to have reflected the unsanitized malicious path."


def test_authentication_and_benign_upload():
    unauthenticated = _post_upload("ordinary.txt", b"ordinary content")
    assert unauthenticated.status_code in (400, 401, 403), "The upload endpoint accepts uploads without authentication"

    headers, fields = _working_auth()
    response = _post_upload("ordinary.txt", b"ordinary content", headers, fields)
    assert response.status_code in (200, 201), "A valid authenticated upload was not accepted"
    assert response.headers.get("Content-Security-Policy") == CSP, "Authenticated upload response is missing the strict CSP header"


def test_authenticated_dynamic_traversal_cannot_escape():
    headers, fields = _working_auth()
    marker = "verifier_" + secrets.token_hex(10)
    target = "/tmp/" + marker
    original = secrets.token_bytes(40)
    replacement = secrets.token_bytes(40)
    with open(target, "wb") as f:
        f.write(original)

    try:
        filenames = ["../../../../../../../../tmp/" + marker, target]
        for filename in filenames:
            response = _post_upload(filename, replacement, headers, fields)
            assert response.status_code in (200, 201, 400, 403), f"Unexpected traversal response status {response.status_code}"
            assert response.headers.get("Content-Security-Policy") == CSP, "Traversal response is missing the strict CSP header"
            if response.status_code in (200, 201):
                assert filename not in response.text, "The service reflected an unsanitized traversal filename"
            with open(target, "rb") as f:
                assert f.read() == original, "The upload handler wrote through a path traversal filename"
    finally:
        try:
            os.unlink(target)
        except FileNotFoundError:
            pass


def test_firewall_script_installs_active_rules():
    script = "/home/user/firewall_setup.sh"

    # Remove relevant active-chain rules before running the submitted script, so
    # preinstalled rules cannot make an empty placeholder script pass.
    for command in (
        ["iptables", "-P", "INPUT", "ACCEPT"],
        ["iptables", "-P", "OUTPUT", "ACCEPT"],
        ["iptables", "-F", "INPUT"],
        ["iptables", "-F", "OUTPUT"],
    ):
        result = subprocess.run(command, capture_output=True, text=True, timeout=5)
        assert result.returncode == 0, f"Unable to prepare firewall for verification: {result.stderr}"

    result = subprocess.run(["bash", script], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"firewall_setup.sh failed when executed: {result.stderr}"

    saved = subprocess.run(["iptables-save", "-t", "filter"], capture_output=True, text=True, timeout=5)
    assert saved.returncode == 0, f"Could not inspect active firewall configuration: {saved.stderr}"
    rules = saved.stdout.splitlines()

    allows_8080 = any(
        line.startswith("-A INPUT ")
        and "-p tcp" in line
        and re.search(r"--dport 8080(?:\s|$)", line)
        and re.search(r"-j ACCEPT(?:\s|$)", line)
        for line in rules
    )
    blocks_1337 = any(
        line.startswith("-A OUTPUT ")
        and "-p tcp" in line
        and (re.search(r"--dport 1337(?:\s|$)", line) or re.search(r"--sport 1337(?:\s|$)", line))
        and (re.search(r"-j DROP(?:\s|$)", line) or re.search(r"-j REJECT(?:\s|$)", line))
        for line in rules
    )

    assert allows_8080, "No active INPUT rule allows incoming TCP connections to port 8080"
    assert blocks_1337, "No active OUTPUT rule blocks TCP traffic associated with backdoor port 1337"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
