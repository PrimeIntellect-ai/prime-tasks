#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import secrets
import shutil
import subprocess
import tempfile

EXTRACTOR = "/home/user/extractor.go"
TARGET = "/home/user/target_bin"
LOG = "/home/user/verification_log.json"


def run_extractor():
    result = subprocess.run(
        ["go", "run", EXTRACTOR],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"Running {EXTRACTOR} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_log():
    with open(LOG, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {LOG} does not contain valid JSON."


def test_extractor_go_exists():
    path = "/home/user/extractor.go"
    assert os.path.isfile(path), f"File {path} is missing. Did you write the Go program?"


def test_extractor_executes_and_generates_log():
    if os.path.lexists(LOG):
        os.remove(LOG)
    run_extractor()
    assert os.path.isfile(LOG), f"File {LOG} is missing. Did you execute the Go program?"


def test_verification_log_exists():
    path = "/home/user/verification_log.json"
    assert os.path.isfile(path), f"File {path} is missing. Did you execute the Go program?"


def test_verification_log_contents():
    path = "/home/user/verification_log.json"
    assert os.path.isfile(path), f"File {path} is missing."

    data = load_log()

    assert "extracted_policy" in data, f"Key 'extracted_policy' missing in {path}."
    assert "sha256" in data, f"Key 'sha256' missing in {path}."
    assert isinstance(data, dict), f"File {path} must contain one JSON object."
    assert set(data.keys()) == {"extracted_policy", "sha256"}, \
        f"File {path} must contain exactly the keys 'extracted_policy' and 'sha256'."

    policy = data["extracted_policy"]
    assert isinstance(policy, dict), "'extracted_policy' must be a JSON object, not a string."

    assert policy.get("env") == "production", f"Expected policy 'env' to be 'production', got {policy.get('env')}"
    assert policy.get("version") == "1.2.3", f"Expected policy 'version' to be '1.2.3', got {policy.get('version')}"
    assert policy.get("signed") is True, f"Expected policy 'signed' to be True, got {policy.get('signed')}"

    expected_payload = '{"env":"production","version":"1.2.3","signed":true}'
    expected_hash = hashlib.sha256(expected_payload.encode("utf-8")).hexdigest()

    assert data["sha256"] == expected_hash, f"Expected sha256 to be '{expected_hash}', got '{data['sha256']}'"


def test_extractor_reads_and_decodes_sec_policy_dynamically():
    nonce = secrets.token_hex(16)
    policy = {
        "env": "verification-" + nonce,
        "version": "9." + str(int(nonce[:4], 16)),
        "signed": False,
        "rules": ["deny-root", nonce],
    }
    payload = json.dumps(policy, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    encoded = base64.b64encode(payload)

    with tempfile.TemporaryDirectory() as tmpdir:
        target_backup = os.path.join(tmpdir, "target_bin")
        section_file = os.path.join(tmpdir, "policy.b64")
        shutil.copy2(TARGET, target_backup)

        try:
            with open(section_file, "wb") as f:
                f.write(encoded)

            update = subprocess.run(
                ["objcopy", "--update-section", f".sec_policy={section_file}", TARGET],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            assert update.returncode == 0, (
                f"Could not prepare dynamic ELF test input: {update.stderr}"
            )

            if os.path.lexists(LOG):
                os.remove(LOG)
            run_extractor()
            assert os.path.isfile(LOG), f"Running {EXTRACTOR} did not create {LOG}."

            data = load_log()
            assert isinstance(data, dict), f"File {LOG} must contain one JSON object."
            assert set(data.keys()) == {"extracted_policy", "sha256"}, \
                f"File {LOG} must contain exactly the required two keys."
            assert data["extracted_policy"] == policy, \
                "The extractor did not decode the policy from the modified .sec_policy section."
            expected_hash = hashlib.sha256(payload).hexdigest()
            assert data["sha256"] == expected_hash, \
                "The extractor did not hash the decoded .sec_policy payload bytes correctly."
        finally:
            shutil.copy2(target_backup, TARGET)
            try:
                run_extractor()
            except Exception:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
