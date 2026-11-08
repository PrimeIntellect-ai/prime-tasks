#!/bin/bash
set -e
mkdir -p /logs/verifier
reward=0
trap 'echo "$reward" > /logs/verifier/reward.txt' EXIT

REAL_EXTRACTOR=/app/extractor.verifier-real
if [ ! -e "$REAL_EXTRACTOR" ]; then
    mv /app/extractor "$REAL_EXTRACTOR"
fi

cat <<'WRAPPER_EOF' > /app/extractor
#!/usr/bin/env python3
import hashlib
import json
import os
import subprocess
import sys

REAL = "/app/extractor.verifier-real"
CONFIG = "/tmp/curator_extractor_cases.json"
LOG = "/tmp/curator_extractor_calls.jsonl"

if len(sys.argv) != 3 or sys.argv[1] != "--analyze":
    sys.exit(1)

path = sys.argv[2]
try:
    with open(path, "rb") as f:
        body = f.read()
    st = os.stat(path)
except OSError:
    sys.exit(1)

digest = hashlib.sha256(body).hexdigest()
record = {
    "argv": sys.argv[1:],
    "path": path,
    "sha256": digest,
    "dev": st.st_dev,
    "ino": st.st_ino,
    "regular": os.path.isfile(path),
}
try:
    fd = os.open(LOG, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
    os.write(fd, (json.dumps(record, sort_keys=True) + "\n").encode())
    os.close(fd)
except OSError:
    pass

cases = {}
try:
    with open(CONFIG, "r", encoding="utf-8") as f:
        cases = json.load(f)
except (OSError, ValueError):
    pass

if digest in cases:
    for entry in cases[digest]:
        print("=== ARCHIVE ENTRY ===")
        print("Filepath: " + entry)
        print("Size: 37")
        print("Type: file")
        print("=====================")
    sys.exit(0)

result = subprocess.run([REAL, "--analyze", path])
sys.exit(result.returncode)
WRAPPER_EOF
chmod 755 /app/extractor
: > /tmp/curator_extractor_calls.jsonl
chmod 666 /tmp/curator_extractor_calls.jsonl

after_wrapper_cleanup() {
    :
}
trap 'echo "$reward" > /logs/verifier/reward.txt' EXIT

cat <<'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import hashlib
import json
import os
import secrets
import subprocess
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
BENIGN_PAYLOAD = b"BENIGN_PAYLOAD_1"
MALICIOUS_PAYLOAD = b"MALICIOUS_PAYLOAD_1"
CALL_LOG = "/tmp/curator_extractor_calls.jsonl"
CASE_CONFIG = "/tmp/curator_extractor_cases.json"
STAGING = "/home/user/staging"
REPOSITORY = "/home/user/repository"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def clear_calls():
    with open(CALL_LOG, "w", encoding="utf-8"):
        pass
    os.chmod(CALL_LOG, 0o666)


def calls():
    result = []
    with open(CALL_LOG, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                result.append(json.loads(line))
    return result


def calls_for(payload):
    digest = sha(payload)
    return [c for c in calls() if c.get("sha256") == digest]


def assert_staged_analysis_and_rename(payload):
    matching = calls_for(payload)
    assert matching, "The service did not invoke /app/extractor for the uploaded body."
    upload_calls = [c for c in matching if os.path.dirname(c["path"]) == STAGING]
    assert upload_calls, f"Extractor was not given a temporary file inside {STAGING}: {matching}"
    call = upload_calls[-1]
    assert call["argv"] == ["--analyze", call["path"]]
    assert call["regular"] is True
    destination = os.path.join(REPOSITORY, sha(payload) + ".pkg")
    st = os.stat(destination)
    assert (st.st_dev, st.st_ino) == (call["dev"], call["ino"]), \
        "Accepted upload was not atomically renamed from its staging inode."
    return call


def assert_rejected_and_removed(payload):
    matching = calls_for(payload)
    assert matching, "The service did not invoke /app/extractor for the malicious body."
    upload_calls = [c for c in matching if os.path.dirname(c["path"]) == STAGING]
    assert upload_calls, f"Malicious upload was not analyzed from {STAGING}: {matching}"
    for call in upload_calls:
        assert not os.path.exists(call["path"]), "Rejected staging file was not deleted."
    assert not os.path.exists(os.path.join(REPOSITORY, sha(payload) + ".pkg"))


@pytest.fixture(scope="module", autouse=True)
def wait_for_service():
    for _ in range(30):
        try:
            requests.get(f"{BASE_URL}/audit", timeout=1)
            return
        except requests.exceptions.RequestException:
            time.sleep(0.5)
    pytest.fail("Service on port 8080 is not responding within the timeout.")


def test_complete_service_behavior():
    # The requested implementation artifact must exist and remain valid Go code.
    assert os.path.isfile("/home/user/curator.go"), "/home/user/curator.go was not created."
    subprocess.run(
        ["go", "build", "-o", "/tmp/curator-verifier-build", "/home/user/curator.go"],
        check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )

    # Preserve the original directory assertions.
    assert os.path.isdir(STAGING), "/home/user/staging directory was not created."
    assert os.path.isdir(REPOSITORY), "/home/user/repository directory was not created."

    # Preserve the original benign upload assertions, while proving extractor use
    # and same-inode staging-to-repository rename behavior.
    clear_calls()
    response = requests.post(f"{BASE_URL}/upload", data=BENIGN_PAYLOAD, timeout=5)
    assert response.status_code == 201, f"Expected 201 Created for benign payload, got {response.status_code}. Response: {response.text}"
    expected_file = os.path.join(REPOSITORY, sha(BENIGN_PAYLOAD) + ".pkg")
    assert os.path.exists(expected_file), f"Expected file {expected_file} to exist in repository."
    with open(expected_file, "rb") as f:
        assert f.read() == BENIGN_PAYLOAD, "Stored file contents do not match the uploaded payload."
    assert_staged_analysis_and_rename(BENIGN_PAYLOAD)

    # Preserve the original malicious upload and cleanup assertions.
    clear_calls()
    response = requests.post(f"{BASE_URL}/upload", data=MALICIOUS_PAYLOAD, timeout=5)
    assert response.status_code == 406, f"Expected 406 Not Acceptable for malicious payload, got {response.status_code}. Response: {response.text}"
    unexpected_file = os.path.join(REPOSITORY, sha(MALICIOUS_PAYLOAD) + ".pkg")
    assert not os.path.exists(unexpected_file), f"Malicious file {unexpected_file} should not exist in repository."
    assert_rejected_and_removed(MALICIOUS_PAYLOAD)
    assert os.listdir(STAGING) == [], f"Staging directory {STAGING} should be empty after processing."

    # Preserve the original exact audit assertion before adding randomized cases.
    clear_calls()
    response = requests.get(f"{BASE_URL}/audit", timeout=5)
    assert response.status_code == 200, f"Expected 200 OK for audit, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Audit response is not valid JSON. Response: {response.text}")
    expected_json = ["bin/startup.sh", "lib/core.so"]
    assert data == expected_json, f"Expected audit response {expected_json}, got {data}"
    benign_audit_calls = [c for c in calls_for(BENIGN_PAYLOAD) if os.path.dirname(c["path"]) == REPOSITORY]
    assert benign_audit_calls, "GET /audit did not re-run /app/extractor on the repository file."

    # Install verifier-derived, unpredictable extractor results. These payloads
    # cannot be handled by special-casing the two legacy constants.
    token = secrets.token_hex(12)
    safe_payloads = [
        (f"random-safe-A-{token}".encode(), [f"docs/{token}/guide.txt", "bin/startup.sh"]),
        (f"random-safe-B-{token}".encode(), [f"config/..hidden-{token}", f"lib/{token}/module.so"]),
        (f"random-safe-C-{token}".encode(), [f"assets/{token}/name with spaces.dat", f"docs/{token}/guide.txt"]),
    ]
    malicious_payloads = [
        (f"random-bad-parent-{token}".encode(), [f"safe/{token}.txt", f"../escape-{token}"]),
        (f"random-bad-backslash-{token}".encode(), [f"folder\\..\\stolen-{token}"]),
        (f"random-bad-absolute-{token}".encode(), [f"/absolute/{token}/target"]),
    ]
    config = {sha(body): entries for body, entries in safe_payloads + malicious_payloads}
    temp_config = CASE_CONFIG + ".new"
    with open(temp_config, "w", encoding="utf-8") as f:
        json.dump(config, f)
    os.replace(temp_config, CASE_CONFIG)
    os.chmod(CASE_CONFIG, 0o644)

    # Concurrent safe uploads exercise unique race-safe temporary creation. Every
    # accepted destination must be the exact inode observed by the extractor.
    clear_calls()
    def upload(item):
        body, _ = item
        return requests.post(f"{BASE_URL}/upload", data=body, timeout=10)

    with concurrent.futures.ThreadPoolExecutor(max_workers=len(safe_payloads)) as pool:
        responses = list(pool.map(upload, safe_payloads))
    for response in responses:
        assert response.status_code == 201, response.text

    staging_paths = []
    staging_inodes = []
    for body, _ in safe_payloads:
        destination = os.path.join(REPOSITORY, sha(body) + ".pkg")
        with open(destination, "rb") as f:
            assert f.read() == body
        call = assert_staged_analysis_and_rename(body)
        staging_paths.append(call["path"])
        staging_inodes.append((call["dev"], call["ino"]))
    assert len(set(staging_paths)) == len(staging_paths), "Concurrent uploads reused a staging pathname."
    assert len(set(staging_inodes)) == len(staging_inodes), "Concurrent uploads reused a staging inode."
    assert os.listdir(STAGING) == [], "Accepted uploads left files in staging."

    # Exercise each prohibited path form with randomized values and a mixed-entry
    # archive, requiring any malicious entry to reject the whole upload.
    for body, _ in malicious_payloads:
        clear_calls()
        response = requests.post(f"{BASE_URL}/upload", data=body, timeout=10)
        assert response.status_code == 406, f"Traversal payload was accepted: {response.status_code} {response.text}"
        assert_rejected_and_removed(body)
        assert os.listdir(STAGING) == [], "Rejected upload left a temporary file in staging."

    # Audit expectations are derived from the randomized extractor configuration.
    expected = {"bin/startup.sh", "lib/core.so"}
    for _, entries in safe_payloads:
        expected.update(entries)
    expected = sorted(expected)

    clear_calls()
    response = requests.get(f"{BASE_URL}/audit", timeout=10)
    assert response.status_code == 200
    try:
        audited = response.json()
    except ValueError:
        pytest.fail(f"Audit response is not valid JSON. Response: {response.text}")
    assert audited == expected, f"Expected sorted unique audit data {expected}, got {audited}"

    repository_files = {
        os.path.join(REPOSITORY, name)
        for name in os.listdir(REPOSITORY)
        if name.endswith(".pkg") and os.path.isfile(os.path.join(REPOSITORY, name))
    }
    analyzed_repository_files = {
        c["path"] for c in calls() if os.path.dirname(c["path"]) == REPOSITORY
    }
    assert repository_files <= analyzed_repository_files, \
        "GET /audit did not execute /app/extractor for every repository .pkg file."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi
