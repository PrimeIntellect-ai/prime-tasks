#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
import re
import subprocess
import tempfile
import urllib.parse
import pytest

EXPLOIT_PATH = "/home/user/exploit.sh"
SERVICE_PATH = "/home/user/service.sh"
TRAFFIC_PATH = "/home/user/traffic.log"
TARGET_HASH_PATH = "/home/user/target_hash.txt"

EXPECTED_SERVICE = b'''#!/bin/bash
# Internal Diagnostic Service v1.0
if [ -z "$1" ]; then
    echo "Usage: $0 <base64_encoded_ip>"
    exit 1
fi

# Decode the input
decoded_ip=$(echo "$1" | base64 -d)

# Perform the diagnostic ping (VULNERABLE TO COMMAND INJECTION)
eval "ping -c 1 $decoded_ip" > /dev/null 2>&1
'''

EXPECTED_TRAFFIC = b'''[2023-10-27 14:32:01] INCOMING HTTP REQUEST
GET /api/diagnostics?token=admin_session&data=MTI3LjAuMC4xO2NhdCAvZXRjL2hvc3Rz HTTP/1.1
Host: internal-router.local
User-Agent: curl/7.68.0
Accept: */*
'''


def assert_exact_hash_file(path, expected_hash):
    assert os.path.isfile(path), f"The file {path} was not created."
    with open(path, "rb") as f:
        actual_content = f.read()
    assert actual_content == (expected_hash + "\n").encode("ascii"), (
        f"{path} must contain exactly the 64-character SHA-256 hash and a newline."
    )
    actual_hash = actual_content.strip().decode("ascii")
    assert actual_hash == expected_hash
    assert len(actual_hash) == 64
    assert re.fullmatch(r"[0-9a-f]{64}", actual_hash)


def attacker_target_from_traffic():
    with open(TRAFFIC_PATH, "r", encoding="utf-8") as f:
        request = next((line for line in f if line.startswith("GET ")), None)
    assert request is not None, "No GET request was found in traffic.log."
    request_target = request.split()[1]
    query = urllib.parse.parse_qs(urllib.parse.urlsplit(request_target).query)
    assert "data" in query and query["data"], "No data query parameter was found."
    decoded = base64.b64decode(query["data"][0], validate=True).decode("utf-8")
    match = re.search(r"\bcat\s+([^\s;&|]+)", decoded)
    assert match, "The intercepted payload does not contain a cat target."
    return match.group(1)


def test_exploit_script_exists_and_executable():
    assert os.path.isfile(EXPLOIT_PATH), f"Exploit script {EXPLOIT_PATH} does not exist."
    assert os.access(EXPLOIT_PATH, os.X_OK), f"Exploit script {EXPLOIT_PATH} is not executable."


def test_exploit_execution_and_result():
    with open(SERVICE_PATH, "rb") as f:
        assert f.read() == EXPECTED_SERVICE, "service.sh was modified."
    with open(TRAFFIC_PATH, "rb") as f:
        assert f.read() == EXPECTED_TRAFFIC, "traffic.log was modified."

    target_path = attacker_target_from_traffic()
    assert os.path.isfile(target_path), f"System file {target_path} is missing."
    with open(target_path, "rb") as f:
        expected_hash = hashlib.sha256(f.read()).hexdigest()

    backup_fd, backup_path = tempfile.mkstemp(prefix="verifier_service_", dir="/tmp")
    os.close(backup_fd)
    log_fd, log_path = tempfile.mkstemp(prefix="verifier_calls_", dir="/tmp")
    os.close(log_fd)

    os.replace(SERVICE_PATH, backup_path)
    wrapper = f'''#!/bin/bash
printf '%s' "$1" | base64 -w0 >> {log_path}
printf '\n' >> {log_path}
exec {backup_path} "$@"
'''
    with open(SERVICE_PATH, "w", encoding="utf-8") as f:
        f.write(wrapper)
    os.chmod(SERVICE_PATH, 0o755)

    try:
        if os.path.exists(TARGET_HASH_PATH):
            os.remove(TARGET_HASH_PATH)
        try:
            subprocess.run([EXPLOIT_PATH], check=True, timeout=10)
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Execution of {EXPLOIT_PATH} failed with return code {e.returncode}.")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Execution of {EXPLOIT_PATH} timed out.")

        # Preserve the original verifier's result check on exploit.sh itself.
        assert_exact_hash_file(TARGET_HASH_PATH, expected_hash)
        with open(log_path, "r", encoding="ascii") as f:
            recorded_lines = [line.rstrip("\n") for line in f]
    finally:
        if os.path.exists(SERVICE_PATH):
            os.remove(SERVICE_PATH)
        os.replace(backup_path, SERVICE_PATH)
        os.chmod(SERVICE_PATH, 0o755)

    assert recorded_lines, "exploit.sh did not invoke /home/user/service.sh."

    replay_succeeded = False
    for recorded in recorded_lines[:50]:
        try:
            supplied_payload = base64.b64decode(recorded, validate=True)
            encoded_argument = supplied_payload.decode("ascii")
            decoded_payload = base64.b64decode(encoded_argument, validate=True).decode("utf-8")
        except (ValueError, UnicodeDecodeError):
            continue

        # Require an actual shell-injection payload that invokes sha256sum.
        if "sha256sum" not in decoded_payload:
            continue
        if not any(marker in decoded_payload for marker in (";", "&&", "||", "\n", "$(", "`")):
            continue

        if os.path.exists(TARGET_HASH_PATH):
            os.remove(TARGET_HASH_PATH)
        try:
            subprocess.run([SERVICE_PATH, encoded_argument], timeout=10)
        except subprocess.TimeoutExpired:
            continue

        try:
            assert_exact_hash_file(TARGET_HASH_PATH, expected_hash)
            replay_succeeded = True
            break
        except AssertionError:
            continue

    assert replay_succeeded, (
        "No Base64 argument passed by exploit.sh independently reproduced the required "
        "command-injection result when supplied to service.sh."
    )

    with open(SERVICE_PATH, "rb") as f:
        assert f.read() == EXPECTED_SERVICE, "service.sh was not restored unchanged."

    for path in (log_path, backup_path):
        if os.path.exists(path):
            os.remove(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
