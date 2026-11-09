#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

import jsonpatch
import pytest

SCRIPT_PATH = "/home/user/api_filter.sh"
VALIDATOR_PATH = "/app/legacy_validator"
CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"


def expected_values(request):
    patched = jsonpatch.apply_patch(
        request["base_record"], request["record_patch"], in_place=False
    )
    raw_status = patched["profile"]["status"]
    assert raw_status in ("active", "inactive")
    return {
        "account_uuid": f"UUID-{patched['user_id']}",
        "role": patched["role"],
        "status": raw_status == "active",
    }


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_evil_corpus_rejected():
    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith('.json')]
    assert len(evil_files) > 0, "No files found in evil corpus"

    failures = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_DIR, filename)
        result = subprocess.run([SCRIPT_PATH, filepath], capture_output=True, text=True)
        if result.returncode == 0:
            failures.append(f"{filename} (exit code 0)")
        if result.stdout != "":
            failures.append(f"{filename} (produced stdout while rejecting)")

    if failures:
        pytest.fail(
            f"Evil corpus rejection failures: {', '.join(failures)}"
        )


def test_clean_corpus_accepted_and_transformed():
    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith('.json')]
    assert len(clean_files) > 0, "No files found in clean corpus"

    failed_files = []

    for filename in clean_files:
        filepath = os.path.join(CLEAN_DIR, filename)

        with open(filepath, 'r') as f:
            try:
                original_data = json.load(f)
            except json.JSONDecodeError:
                continue

        expected = expected_values(original_data)
        result = subprocess.run([SCRIPT_PATH, filepath], capture_output=True, text=True)

        if result.returncode != 0:
            failed_files.append(f"{filename} (exit code {result.returncode})")
            continue

        try:
            output_data = json.loads(result.stdout)
        except json.JSONDecodeError:
            failed_files.append(f"{filename} (invalid JSON output)")
            continue

        if "account_uuid" not in output_data:
            failed_files.append(f"{filename} (missing account_uuid)")
            continue

        if not output_data["account_uuid"].startswith("UUID-"):
            failed_files.append(f"{filename} (invalid account_uuid format)")
            continue

        if "profile" in output_data:
            failed_files.append(f"{filename} (profile object not removed)")
            continue

        if "status" not in output_data:
            failed_files.append(f"{filename} (missing status at root)")
            continue

        if not isinstance(output_data["status"], bool):
            failed_files.append(f"{filename} (status is not a boolean)")
            continue

        if output_data.get("role") == "admin":
            failed_files.append(f"{filename} (role is admin)")
            continue

        if output_data["account_uuid"] != expected["account_uuid"]:
            failed_files.append(f"{filename} (incorrect account_uuid)")
            continue

        if output_data.get("role") != expected["role"]:
            failed_files.append(f"{filename} (incorrect patched role)")
            continue

        if output_data["status"] is not expected["status"]:
            failed_files.append(f"{filename} (incorrect migrated status)")
            continue

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} clean-file failures: {', '.join(failed_files)}"
        )


def validator_accepts(token):
    return subprocess.run(
        [VALIDATOR_PATH, token], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    ).returncode == 0


def find_token(want_valid):
    for _ in range(1000):
        token = f"TOK-{secrets.randbits(32):08x}"
        if validator_accepts(token) == want_valid:
            return token
    pytest.fail("Could not generate a token with the requested validator result")


def test_generated_inputs_exercise_validation_and_patch(tmp_path):
    valid_token = find_token(True)
    invalid_token = find_token(False)
    original_id = secrets.randbelow(900000) + 100000
    patched_id = secrets.randbelow(900000) + 1000000
    patched_role = f"viewer-{secrets.token_hex(6)}"
    patched_status = secrets.choice(["active", "inactive"])

    request = {
        "auth_token": valid_token,
        "base_record": {
            "user_id": original_id,
            "role": "editor",
            "profile": {"status": "active"},
        },
        "record_patch": [
            {"op": "replace", "path": "/user_id", "value": patched_id},
            {"op": "replace", "path": "/role", "value": patched_role},
            {"op": "replace", "path": "/profile/status", "value": patched_status},
        ],
    }
    expected = expected_values(request)
    valid_path = tmp_path / f"request_{secrets.token_hex(8)}.json"
    valid_path.write_text(json.dumps(request))

    result = subprocess.run([SCRIPT_PATH, str(valid_path)], capture_output=True, text=True)
    assert result.returncode == 0, f"Generated valid request rejected: {result.stderr}"
    output = json.loads(result.stdout)
    assert output.get("account_uuid") == expected["account_uuid"]
    assert output.get("role") == expected["role"]
    assert output.get("status") is expected["status"]
    assert "profile" not in output

    rejected_requests = []

    bad_token_request = dict(request)
    bad_token_request["auth_token"] = invalid_token
    rejected_requests.append(json.dumps(bad_token_request))

    admin_request = json.loads(json.dumps(request))
    admin_request["record_patch"] = [
        {"op": "replace", "path": "/role", "value": "admin"}
    ]
    rejected_requests.append(json.dumps(admin_request))
    rejected_requests.append('{"auth_token":')

    for index, contents in enumerate(rejected_requests):
        path = tmp_path / f"request_{index}_{secrets.token_hex(8)}.json"
        path.write_text(contents)
        rejected = subprocess.run([SCRIPT_PATH, str(path)], capture_output=True, text=True)
        assert rejected.returncode != 0, f"Generated invalid request {index} was accepted"
        assert rejected.stdout == "", f"Generated invalid request {index} produced stdout"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
