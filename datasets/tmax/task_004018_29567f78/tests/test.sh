#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest

VENDOR_SCRIPT = "/app/vendor/bash-router-1.2.0/router.sh"
VALIDATOR_SCRIPT = "/home/user/api_validator.sh"


def run_validator(path):
    return subprocess.run(
        [VALIDATOR_SCRIPT, str(path)],
        capture_output=True,
        timeout=10,
    )


def expected_valid(document):
    if type(document) is not dict:
        return False
    if "api_version" not in document or type(document["api_version"]) is not int:
        return False
    if document["api_version"] <= 1:
        return False
    if document.get("request_type") not in ("mutation", "query"):
        return False
    if "payload" not in document or type(document["payload"]) is not dict:
        return False

    payload = document["payload"]
    if document["request_type"] == "mutation":
        return (
            "user_id" in payload
            and type(payload["user_id"]) is str
            and len(payload["user_id"]) > 0
            and payload["user_id"].startswith("USR-")
            and "action_code" in payload
            and type(payload["action_code"]) is int
            and 100 <= payload["action_code"] <= 199
        )

    return (
        "search_term" in payload
        and type(payload["search_term"]) is str
        and len(payload["search_term"]) <= 20
    )


def test_router_script_fixed():
    """Preserve the original required positive health-check assertion."""
    assert os.path.isfile(VENDOR_SCRIPT), f"Vendor script {VENDOR_SCRIPT} is missing."

    test_conf_dir = "/tmp/test_conf_pytest"
    os.makedirs(test_conf_dir, exist_ok=True)

    env = os.environ.copy()
    env["ROUTER_CONFIG_PATH"] = test_conf_dir

    result = subprocess.run(
        [VENDOR_SCRIPT, "--health-check"],
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
    )

    assert result.returncode == 0, (
        f"router.sh failed to start with custom ROUTER_CONFIG_PATH. "
        f"Exit code: {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}"
    )


def test_router_uses_dynamic_config_path_and_rejects_missing_directory():
    """Ensure the result depends on the environment-selected directory."""
    token = uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix=f"router_{token}_") as existing:
        env = os.environ.copy()
        env["ROUTER_CONFIG_PATH"] = existing
        good = subprocess.run(
            [VENDOR_SCRIPT, "--health-check"],
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert good.returncode == 0, good.stdout + good.stderr

        missing = os.path.join(tempfile.gettempdir(), f"missing_router_config_{uuid.uuid4().hex}")
        assert not os.path.exists(missing)
        env["ROUTER_CONFIG_PATH"] = missing
        bad = subprocess.run(
            [VENDOR_SCRIPT, "--health-check"],
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert bad.returncode != 0, (
            "router.sh succeeded even though ROUTER_CONFIG_PATH selected a missing directory"
        )


def test_api_validator_exists():
    assert os.path.isfile(VALIDATOR_SCRIPT), f"Validator script {VALIDATOR_SCRIPT} is missing."
    assert os.access(VALIDATOR_SCRIPT, os.X_OK), f"Validator script {VALIDATOR_SCRIPT} is not executable."


def test_api_validator_adversarial_corpus():
    """Preserve all checks against the supplied development corpus."""
    clean_dir = Path("/home/user/corpora/clean")
    evil_dir = Path("/home/user/corpora/evil")

    assert clean_dir.is_dir(), f"Clean corpus directory {clean_dir} is missing."
    assert evil_dir.is_dir(), f"Evil corpus directory {evil_dir} is missing."

    clean_files = list(clean_dir.glob("*.json"))
    evil_files = list(evil_dir.glob("*.json"))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failures = []
    for clean_file in clean_files:
        result = run_validator(clean_file)
        if result.returncode != 0:
            clean_failures.append(clean_file.name)

    evil_failures = []
    for evil_file in evil_files:
        result = run_validator(evil_file)
        if result.returncode == 0:
            evil_failures.append(evil_file.name)

    error_msgs = []
    if clean_failures:
        error_msgs.append(
            f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: "
            + ", ".join(clean_failures)
        )
    if evil_failures:
        error_msgs.append(
            f"{len(evil_failures)} of {len(evil_files)} evil bypassed/accepted: "
            + ", ".join(evil_failures)
        )
    if error_msgs:
        pytest.fail("Adversarial corpus validation failed: " + "; ".join(error_msgs))


def test_api_validator_generated_payloads_at_unpredictable_paths():
    """Exercise schema behavior independently of the fixed corpus names and paths."""
    documents = [
        {"api_version": 2, "request_type": "query", "payload": {"search_term": ""}},
        {"api_version": 7, "request_type": "query", "payload": {"search_term": "x" * 20}},
        {"api_version": 2, "request_type": "mutation", "payload": {"user_id": "USR-", "action_code": 100}},
        {"api_version": 999, "request_type": "mutation", "payload": {"user_id": "USR-random", "action_code": 199}, "extra": True},
        [],
        None,
        {"api_version": True, "request_type": "query", "payload": {"search_term": "ok"}},
        {"api_version": 2.0, "request_type": "query", "payload": {"search_term": "ok"}},
        {"api_version": 2, "request_type": "query", "payload": {"search_term": "x" * 21}},
        {"api_version": 2, "request_type": "query", "payload": {"search_term": 12}},
        {"api_version": 2, "request_type": "query", "payload": []},
        {"api_version": 2, "request_type": "mutation", "payload": {"user_id": "USR-x", "action_code": True}},
        {"api_version": 2, "request_type": "mutation", "payload": {"user_id": "USR-x", "action_code": 100.0}},
        {"api_version": 2, "request_type": "mutation", "payload": {"user_id": "USR-x", "action_code": 150}},
    ]

    rng = random.Random(904271)
    version_values = [None, True, False, "2", 1, 2, 3, 20, 2.5]
    request_values = [None, "query", "mutation", "delete", 4]
    search_values = [None, 5, "", "a", "q" * 20, "q" * 21, "snowman-☃"]
    user_values = [None, 9, "", "USR-", "USR-123", "ADMIN-1", "xUSR-1"]
    action_values = [None, True, "150", 99, 100, 150, 199, 200, 150.0]

    for _ in range(80):
        request_type = rng.choice(request_values)
        payload = {}
        if rng.random() < 0.8:
            payload["search_term"] = rng.choice(search_values)
        if rng.random() < 0.8:
            payload["user_id"] = rng.choice(user_values)
        if rng.random() < 0.8:
            payload["action_code"] = rng.choice(action_values)
        document = {
            "api_version": rng.choice(version_values),
            "request_type": request_type,
            "payload": payload if rng.random() < 0.9 else rng.choice([None, [], "payload"]),
        }
        if rng.random() < 0.15:
            document.pop(rng.choice(list(document.keys())))
        documents.append(document)

    with tempfile.TemporaryDirectory(prefix=f"validator_{uuid.uuid4().hex}_") as directory:
        directory = Path(directory)
        shared_path = directory / f"changing_{uuid.uuid4().hex}.input"

        for index, document in enumerate(documents):
            expected = expected_valid(document)
            encoded = json.dumps(document, ensure_ascii=False)

            dynamic_path = directory / f"case_{uuid.uuid4().hex}_{index}.data"
            dynamic_path.write_text(encoded, encoding="utf-8")
            result = run_validator(dynamic_path)
            wanted = 0 if expected else 1
            assert result.returncode == wanted, (
                f"Generated case {index} expected exit {wanted}, got {result.returncode}; "
                f"document={encoded!r}; stdout={result.stdout!r}; stderr={result.stderr!r}"
            )

            # Reuse one path for changing valid and invalid contents, preventing
            # decisions based solely on a discovered pathname.
            shared_path.write_text(encoded, encoding="utf-8")
            shared_result = run_validator(shared_path)
            assert shared_result.returncode == wanted, (
                f"Validator did not follow changing content at a shared path for case {index}"
            )


def test_api_validator_rejects_generated_malformed_json():
    malformed_inputs = [
        "",
        "{",
        '{"api_version":2,}',
        '{"api_version":2 "request_type":"query"}',
        '{"api_version":2,"request_type":"query","payload":{"search_term":"ok"}} trailing',
        '[1, 2,',
    ]
    with tempfile.TemporaryDirectory(prefix=f"malformed_{uuid.uuid4().hex}_") as directory:
        path = Path(directory) / f"changing_{uuid.uuid4().hex}.json"
        for content in malformed_inputs:
            path.write_text(content, encoding="utf-8")
            result = run_validator(path)
            assert result.returncode == 1, (
                f"Malformed JSON must produce exit code 1, got {result.returncode} for {content!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
