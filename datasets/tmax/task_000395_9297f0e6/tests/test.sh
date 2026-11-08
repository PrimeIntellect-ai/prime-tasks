#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import base64
import hashlib
import secrets
import shutil
import subprocess
import pytest

LOG_FILE = "/home/user/tampered.log"
ARTIFACTS_DIR = "/home/user/artifacts"
SCANNER_FILE = "/home/user/scanner.py"
CONTROLLED_EXPECTED = ""


def normalized(content):
    return content.strip() + "\n" if content.strip() else ""


@pytest.fixture(scope="session", autouse=True)
def run_scanner_on_controlled_artifacts():
    global CONTROLLED_EXPECTED

    assert os.path.exists(SCANNER_FILE), f"The scanner {SCANNER_FILE} was not created."
    scanner_stat = os.lstat(SCANNER_FILE)
    assert stat.S_ISREG(scanner_stat.st_mode), f"{SCANNER_FILE} is not a regular file."

    if os.path.lexists(ARTIFACTS_DIR):
        if os.path.isdir(ARTIFACTS_DIR) and not os.path.islink(ARTIFACTS_DIR):
            shutil.rmtree(ARTIFACTS_DIR)
        else:
            os.unlink(ARTIFACTS_DIR)
    os.makedirs(ARTIFACTS_DIR)

    token = secrets.token_hex(8)
    fixtures = [
        (f"zeta_{token}.txt", os.urandom(31), True),
        (f"alpha_{token}.txt", os.urandom(7), True),
        (f"middle_{token}.txt", os.urandom(64), True),
        (f"valid_a_{token}.txt", os.urandom(23), False),
        (f"valid_b_{token}.txt", os.urandom(48), False),
    ]

    expected_entries = []
    for filename, payload, tampered in fixtures:
        actual_digest = hashlib.sha256(payload).hexdigest()
        if tampered:
            replacement = "0" if actual_digest[0] != "0" else "1"
            supplied_digest = replacement + actual_digest[1:]
            expected_entries.append(f"{filename}:{payload.hex()}")
        else:
            supplied_digest = actual_digest

        contents = (
            "Encoding: base64\n"
            f"Checksum: {supplied_digest}\n"
            f"Payload: {base64.b64encode(payload).decode('ascii')}\n"
        )
        with open(os.path.join(ARTIFACTS_DIR, filename), "w") as artifact:
            artifact.write(contents)

    expected_entries.sort()
    CONTROLLED_EXPECTED = "\n".join(expected_entries) + "\n"
    original_artifacts = {
        name: open(os.path.join(ARTIFACTS_DIR, name), "rb").read()
        for name in os.listdir(ARTIFACTS_DIR)
    }

    try:
        result = subprocess.run(
            ["python3", SCANNER_FILE],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{SCANNER_FILE} did not finish within 20 seconds.")

    assert result.returncode == 0, (
        f"{SCANNER_FILE} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )

    assert os.path.isdir(ARTIFACTS_DIR), "The scanner removed the artifacts directory."
    current_names = sorted(os.listdir(ARTIFACTS_DIR))
    assert current_names == sorted(original_artifacts), "The scanner modified the artifact set."
    for name, original_content in original_artifacts.items():
        path = os.path.join(ARTIFACTS_DIR, name)
        assert os.path.isfile(path), f"The scanner removed or replaced artifact {name}."
        with open(path, "rb") as artifact:
            assert artifact.read() == original_content, f"The scanner modified artifact {name}."

    assert os.path.exists(LOG_FILE), f"The log file {LOG_FILE} was not created."
    assert os.path.isfile(LOG_FILE), f"{LOG_FILE} is not a regular file."
    with open(LOG_FILE, "r") as log:
        actual = log.read()
    assert normalized(actual) == normalized(CONTROLLED_EXPECTED), (
        "The scanner did not produce the expected result for verifier-generated artifacts.\n"
        f"Expected:\n{CONTROLLED_EXPECTED}\nActual:\n{actual}"
    )


def get_expected_tampered_log():
    tampered_entries = []

    if not os.path.exists(ARTIFACTS_DIR):
        return ""

    for filename in os.listdir(ARTIFACTS_DIR):
        filepath = os.path.join(ARTIFACTS_DIR, filename)
        if not os.path.isfile(filepath):
            continue

        with open(filepath, 'r') as f:
            lines = f.read().strip().split('\n')

        checksum = None
        payload_b64 = None
        for line in lines:
            if line.startswith("Checksum:"):
                checksum = line.split(":", 1)[1].strip()
            elif line.startswith("Payload:"):
                payload_b64 = line.split(":", 1)[1].strip()

        if checksum and payload_b64:
            decoded_bytes = base64.b64decode(payload_b64)
            calculated_hash = hashlib.sha256(decoded_bytes).hexdigest()

            if calculated_hash != checksum:
                tampered_entries.append(f"{filename}:{decoded_bytes.hex()}")

    tampered_entries.sort()
    if not tampered_entries:
        return ""
    return "\n".join(tampered_entries) + "\n"


def test_tampered_log_exists():
    assert os.path.exists(LOG_FILE), f"The log file {LOG_FILE} was not created."
    assert os.path.isfile(LOG_FILE), f"{LOG_FILE} is not a regular file."


def test_tampered_log_contents():
    expected_content = get_expected_tampered_log()

    with open(LOG_FILE, 'r') as f:
        actual_content = f.read()

    # Standardize line endings for comparison
    actual_content_normalized = actual_content.strip() + "\n" if actual_content.strip() else ""
    expected_content_normalized = expected_content.strip() + "\n" if expected_content.strip() else ""

    assert actual_content_normalized == expected_content_normalized, (
        f"The contents of {LOG_FILE} do not match the expected output.\n"
        f"Expected:\n{expected_content_normalized}\n"
        f"Actual:\n{actual_content_normalized}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
