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
set -u
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_original_requirements.py
import hashlib
import os
import re
import subprocess

import pytest
import requests

URL = "http://127.0.0.1:9090/track"


def test_cron_file_exists_and_correct():
    cron_file = "/home/user/log_rotate.cron"
    assert os.path.exists(cron_file), f"Cron file {cron_file} does not exist."

    with open(cron_file, "r") as f:
        content = f.read().strip()

    pattern = r"^0\s+0\s+\*\s+\*\s+\*\s+/usr/bin/logrotate\s+-f\s+/etc/logrotate\.d/tracker$"
    assert re.match(pattern, content), f"Cron file content does not match expected pattern. Got: {content}"


def test_hasher_artifact_is_executable_and_behaves_as_documented():
    path = "/app/config_hasher"
    assert os.path.isfile(path), f"Hasher {path} does not exist or is not a regular file."
    assert os.access(path, os.X_OK), f"Hasher {path} is not executable."
    data = b"verifier-artifact-check\nvalue=17"
    result = subprocess.run([path], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert result.returncode == 0, result.stderr.decode("utf-8", "replace")
    assert result.stdout.decode() == hashlib.md5(data).hexdigest().upper()


def test_http_server_valid_request():
    payload = {
        "timestamp": "2023-10-25T14:30:00Z",
        "service": "api-gateway",
        "config_data": "max_connections=100\ntimeout=30",
    }
    try:
        response = requests.post(URL, json=payload, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")
    assert response.status_code == 200, f"Expected HTTP 200 for valid payload, got {response.status_code}"


def test_http_server_invalid_service():
    payload = {
        "timestamp": "2023-10-25T14:30:00Z",
        "service": "my service",
        "config_data": "test",
    }
    try:
        response = requests.post(URL, json=payload, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")
    assert response.status_code == 400, f"Expected HTTP 400 for invalid service, got {response.status_code}"


def test_http_server_invalid_timestamp():
    payload = {
        "timestamp": "25-10-2023",
        "service": "api-gateway",
        "config_data": "test",
    }
    try:
        response = requests.post(URL, json=payload, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")
    assert response.status_code == 400, f"Expected HTTP 400 for invalid timestamp, got {response.status_code}"


def test_log_file_content():
    log_file = "/home/user/tracked_configs.log"
    assert os.path.exists(log_file), f"Log file {log_file} does not exist."
    with open(log_file, "r") as f:
        content = f.read()

    expected_hash = hashlib.md5(b"max_connections=100\ntimeout=30").hexdigest().upper()
    expected_line = f"[2023-10-25T14:30:00Z] api-gateway | SIGNATURE: {expected_hash}"
    assert expected_line in content, f"Expected line '{expected_line}' not found in log file. Content: {content}"
TEST_EOF

ok=1
if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_original_requirements.py -x --tb=short; then
    ok=0
fi

backup="/app/config_hasher.verifier-backup.$$"
call_log="/tmp/config_hasher_calls.$$"
nonce="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"

restore_hasher() {
    if [ -e "$backup" ]; then
        rm -f /app/config_hasher
        mv "$backup" /app/config_hasher
    fi
    rm -f "$call_log"
}
trap restore_hasher EXIT

if [ "$ok" -eq 1 ]; then
    mv /app/config_hasher "$backup"
    : > "$call_log"
    chmod 666 "$call_log"

    cat > /app/config_hasher <<WRAPPER_EOF
#!/usr/bin/env python3
import base64
import hashlib
import sys

data = sys.stdin.buffer.read()
with open("$call_log", "ab") as calls:
    calls.write(base64.b64encode(data) + b"\\n")
sys.stdout.write(hashlib.sha256(bytes.fromhex("$nonce") + data).hexdigest().upper())
WRAPPER_EOF
    chmod 755 /app/config_hasher

    export VERIFIER_NONCE="$nonce"
    export VERIFIER_CALL_LOG="$call_log"

    cat <<'TEST_EOF' > /tmp/test_dynamic_behavior.py
import base64
import hashlib
import os
import secrets
import string

import requests

URL = "http://127.0.0.1:9090/track"
LOG = "/home/user/tracked_configs.log"
CALL_LOG = os.environ["VERIFIER_CALL_LOG"]
NONCE = bytes.fromhex(os.environ["VERIFIER_NONCE"])


def log_bytes():
    if not os.path.exists(LOG):
        return b""
    with open(LOG, "rb") as f:
        return f.read()


def calls():
    with open(CALL_LOG, "rb") as f:
        return [base64.b64decode(line) for line in f.read().splitlines()]


def signature(text):
    return hashlib.sha256(NONCE + text.encode("utf-8")).hexdigest().upper()


def post(payload):
    return requests.post(URL, json=payload, timeout=3)


def random_service(length):
    alphabet = string.ascii_lowercase + string.digits + "_-"
    return "".join(secrets.choice(alphabet) for _ in range(length))


def random_timestamp():
    year = secrets.choice(range(2001, 2035))
    month = secrets.choice(range(1, 13))
    day = secrets.choice(range(1, 29))
    hour = secrets.choice(range(24))
    minute = secrets.choice(range(60))
    second = secrets.choice(range(60))
    return f"{year:04d}-{month:02d}-{day:02d}T{hour:02d}:{minute:02d}:{second:02d}Z"


def test_random_valid_payloads_invoke_hasher_with_exact_stdin_and_append_exactly_one_line():
    token = secrets.token_hex(12)
    payloads = [
        (random_timestamp(), random_service(3), ""),
        (random_timestamp(), random_service(16), f"alpha={token}\nbeta={secrets.randbelow(1000000)}"),
        (random_timestamp(), random_service(secrets.choice(range(4, 16))), f"unicode=λ-{token}\nspaces = retained  "),
        (random_timestamp(), random_service(secrets.choice(range(3, 17))), secrets.token_urlsafe(57)),
    ]

    expected_inputs = []
    for timestamp, service, config_data in payloads:
        before_log = log_bytes()
        before_calls = calls()
        response = post({"timestamp": timestamp, "service": service, "config_data": config_data})
        assert response.status_code == 200

        expected_line = f"[{timestamp}] {service} | SIGNATURE: {signature(config_data)}\n".encode("utf-8")
        after_log = log_bytes()
        after_calls = calls()
        assert after_log == before_log + expected_line, "A valid request must append exactly one correctly formatted line"
        assert len(after_calls) == len(before_calls) + 1, "The server did not invoke /app/config_hasher exactly once"
        assert after_calls[-1] == config_data.encode("utf-8"), "config_data was not passed strictly via hasher stdin"
        expected_inputs.append(config_data.encode("utf-8"))

    observed = calls()
    for value in expected_inputs:
        assert value in observed


def test_random_invalid_services_are_rejected_without_hashing_or_logging():
    valid_timestamp = random_timestamp()
    invalid_services = [
        random_service(2),
        random_service(16) + secrets.choice(string.ascii_lowercase),
        "UP" + random_service(3),
        random_service(3) + ".bad",
        random_service(3) + " bad",
        random_service(3) + "/bad",
    ]
    for service in invalid_services:
        before_log = log_bytes()
        before_calls = calls()
        response = post({"timestamp": valid_timestamp, "service": service, "config_data": secrets.token_hex(18)})
        assert response.status_code == 400, f"Invalid service accepted: {service!r}"
        assert log_bytes() == before_log
        assert calls() == before_calls


def test_random_invalid_timestamps_are_rejected_without_hashing_or_logging():
    service = random_service(8)
    base = random_timestamp()
    invalid_timestamps = [
        base[:-1],
        base + secrets.choice(string.ascii_letters),
        base.replace("T", " "),
        base.replace("Z", "+00:00"),
        base[0:5] + base[6:],
        base + "\n",
        f"{secrets.randbelow(9999):04d}-1-01T00:00:00Z",
    ]
    for timestamp in invalid_timestamps:
        before_log = log_bytes()
        before_calls = calls()
        response = post({"timestamp": timestamp, "service": service, "config_data": secrets.token_hex(18)})
        assert response.status_code == 400, f"Invalid timestamp accepted: {timestamp!r}"
        assert log_bytes() == before_log
        assert calls() == before_calls
TEST_EOF

    if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_dynamic_behavior.py -x --tb=short; then
        ok=0
    fi
fi

restore_hasher
trap - EXIT

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
