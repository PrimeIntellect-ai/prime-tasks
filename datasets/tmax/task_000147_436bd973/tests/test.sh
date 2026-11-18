#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import base64
import pytest
import re
import shutil
import subprocess

TRAFFIC_LOG_PATH = "/home/user/traffic_capture.json"
REPORT_PATH = "/home/user/report.json"
MALWARE_PATH = "/home/user/malware.elf"


def canonical_traffic_log():
    elf_header = b'\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00'
    elf_body = b'\x02\x00\x3e\x00\x01\x00\x00\x00\x10\x11\x40\x00\x00\x00\x00\x00'
    dummy_elf = elf_header + elf_body + b'somejunkdata\x00C2_SERVER=https://10.99.88.77/c2/register\x00morejunk'
    encrypted_elf = bytes(b ^ 137 for b in dummy_elf)
    b64_payload = base64.b64encode(encrypted_elf).decode('utf-8')
    sqli_payload = f"SELECT * FROM users WHERE id=1 UNION SELECT 1, '{b64_payload}' --"
    malicious_jwt = "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJyb2xlIjoiYWRtaW4ifQ."
    return [
        {
            "timestamp": "2023-10-24T10:00:00Z",
            "method": "GET",
            "headers": {"Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoidXNlciJ9.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"},
            "data": "user=test"
        },
        {
            "timestamp": "2023-10-24T10:05:12Z",
            "method": "POST",
            "headers": {"Authorization": f"Bearer {malicious_jwt}"},
            "data": sqli_payload
        },
        {
            "timestamp": "2023-10-24T10:06:00Z",
            "method": "POST",
            "headers": {"Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiZ3Vlc3QifQ.wrong_sig"},
            "data": "action=ping"
        }
    ]


def remove_path(path):
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)


def restore_canonical_capture():
    remove_path(TRAFFIC_LOG_PATH)
    with open(TRAFFIC_LOG_PATH, 'w', encoding='utf-8') as f:
        json.dump(canonical_traffic_log(), f, indent=2)
    os.chmod(TRAFFIC_LOG_PATH, 0o644)


def derive_truth():
    """Derive the expected truth values from the restored, trusted traffic log."""
    assert os.path.exists(TRAFFIC_LOG_PATH), f"Missing {TRAFFIC_LOG_PATH}"
    with open(TRAFFIC_LOG_PATH, 'r', encoding='utf-8') as f:
        traffic_log = json.load(f)

    malicious_jwt = None
    sqli_payload = None

    for entry in traffic_log:
        auth_header = entry.get("headers", {}).get("Authorization", "")
        if auth_header.startswith("Bearer "):
            token = auth_header[len("Bearer "):]
            parts = token.split(".")
            if len(parts) >= 2:
                try:
                    header_pad = parts[0] + "=" * ((4 - len(parts[0]) % 4) % 4)
                    payload_pad = parts[1] + "=" * ((4 - len(parts[1]) % 4) % 4)
                    header = json.loads(base64.urlsafe_b64decode(header_pad).decode('utf-8'))
                    payload = json.loads(base64.urlsafe_b64decode(payload_pad).decode('utf-8'))
                    if header.get("alg", "").lower() == "none" and payload.get("role") == "admin":
                        malicious_jwt = token
                        sqli_payload = entry.get("data", "")
                        break
                except Exception:
                    continue

    assert malicious_jwt is not None, "Could not find malicious JWT in traffic log."
    assert sqli_payload is not None, "Could not find SQLi payload in traffic log."

    match = re.search(r"'([A-Za-z0-9+/=]+)'", sqli_payload)
    assert match is not None, "Could not find base64 payload in SQLi data."
    encrypted_elf = base64.b64decode(match.group(1))

    xor_key = None
    decrypted_elf = None
    for k in range(256):
        dec = bytes([b ^ k for b in encrypted_elf])
        if dec.startswith(b'\x7fELF'):
            xor_key = k
            decrypted_elf = dec
            break

    assert xor_key is not None, "Could not find XOR key to decrypt ELF."

    c2_server_address = None
    c2_match = re.search(b'C2_SERVER=([^\x00]+)', decrypted_elf)
    if c2_match:
        c2_server_address = c2_match.group(1).decode('utf-8', errors='ignore')
    assert c2_server_address is not None, "Could not find C2 server address in decrypted ELF."

    return {
        "malicious_jwt": malicious_jwt,
        "xor_key_decimal": xor_key,
        "c2_server_address": c2_server_address,
        "decrypted_elf": decrypted_elf
    }


def artifacts_match(truth):
    try:
        if not os.path.isfile(REPORT_PATH) or not os.path.isfile(MALWARE_PATH):
            return False
        with open(REPORT_PATH, 'r', encoding='utf-8') as f:
            report = json.load(f)
        with open(MALWARE_PATH, 'rb') as f:
            malware = f.read()
        return (
            report.get("malicious_jwt") == truth["malicious_jwt"] and
            report.get("xor_key_decimal") == truth["xor_key_decimal"] and
            report.get("c2_server_address") == truth["c2_server_address"] and
            malware.startswith(b'\x7fELF') and
            malware == truth["decrypted_elf"]
        )
    except Exception:
        return False


def find_python_scripts():
    candidates = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for name in files:
            path = os.path.join(root, name)
            if path in (TRAFFIC_LOG_PATH, REPORT_PATH, MALWARE_PATH) or os.path.islink(path):
                continue
            try:
                if not os.path.isfile(path) or os.path.getsize(path) > 1024 * 1024:
                    continue
                with open(path, 'rb') as f:
                    first = f.readline(256)
                if name.endswith('.py') or (first.startswith(b'#!') and b'python' in first.lower()):
                    candidates.append(path)
            except OSError:
                continue
    candidates.sort(key=lambda p: (os.path.basename(p) != 'analyze.py', p))
    return candidates


@pytest.fixture(scope="module", autouse=True)
def prepared_submission():
    restore_canonical_capture()
    truth = derive_truth()
    candidates = find_python_scripts()
    assert candidates, "No Python analysis script was found under /home/user."

    errors = []
    for script in candidates:
        restore_canonical_capture()
        remove_path(REPORT_PATH)
        remove_path(MALWARE_PATH)
        try:
            result = subprocess.run(
                ['runuser', '-u', 'user', '--', 'env', 'HOME=/home/user',
                 'PATH=/usr/local/bin:/usr/bin:/bin', 'python3', script],
                cwd='/home/user', stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=30, text=True
            )
            if result.returncode == 0 and artifacts_match(truth):
                restore_canonical_capture()
                return truth
            errors.append(f"{script}: exit {result.returncode}")
        except subprocess.TimeoutExpired:
            errors.append(f"{script}: timed out")
        except Exception as exc:
            errors.append(f"{script}: {exc}")

    pytest.fail("No submitted Python script produced the required artifacts from the trusted capture. " + "; ".join(errors))


@pytest.fixture(scope="module")
def truth_data(prepared_submission):
    return prepared_submission


def test_report_exists_and_valid_json():
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."
    assert os.path.isfile(REPORT_PATH), f"Report path {REPORT_PATH} is not a file."
    try:
        with open(REPORT_PATH, 'r', encoding='utf-8') as f:
            json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Report file {REPORT_PATH} is not valid JSON.")


def test_report_contents(truth_data):
    with open(REPORT_PATH, 'r', encoding='utf-8') as f:
        report = json.load(f)

    assert "malicious_jwt" in report, "Report missing 'malicious_jwt' key."
    assert report["malicious_jwt"] == truth_data["malicious_jwt"], "Incorrect malicious_jwt in report."
    assert "xor_key_decimal" in report, "Report missing 'xor_key_decimal' key."
    assert report["xor_key_decimal"] == truth_data["xor_key_decimal"], "Incorrect xor_key_decimal in report."
    assert "c2_server_address" in report, "Report missing 'c2_server_address' key."
    assert report["c2_server_address"] == truth_data["c2_server_address"], "Incorrect c2_server_address in report."


def test_malware_elf_exists_and_valid(truth_data):
    assert os.path.exists(MALWARE_PATH), f"Malware file {MALWARE_PATH} does not exist."
    assert os.path.isfile(MALWARE_PATH), f"Malware path {MALWARE_PATH} is not a file."
    with open(MALWARE_PATH, 'rb') as f:
        content = f.read()
    assert content.startswith(b'\x7fELF'), "The saved malware file does not start with ELF magic bytes."
    assert content == truth_data["decrypted_elf"], "The saved malware file content does not match the fully decrypted payload."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
