#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import copy
import hashlib
import hmac
import json
import os
import subprocess

NEW_KEY = b"rotated_secure_key_2024"


def load_logs(filepath):
    if not os.path.isfile(filepath):
        return []
    with open(filepath, "r") as f:
        return [json.loads(line) for line in f if line.strip()]


def signed_with_new_key(token):
    try:
        parts = token.split(".")
        if len(parts) != 3:
            return False
        header_part, payload_part, signature_part = parts
        padding = "=" * (-len(header_part) % 4)
        header = json.loads(base64.urlsafe_b64decode(header_part + padding))
        if header.get("alg") != "HS256":
            return False
        signing_input = (header_part + "." + payload_part).encode()
        expected = hmac.new(NEW_KEY, signing_input, hashlib.sha256).digest()
        padding = "=" * (-len(signature_part) % 4)
        actual = base64.urlsafe_b64decode(signature_part + padding)
        return hmac.compare_digest(actual, expected)
    except Exception:
        return False


def expected_outputs():
    source = load_logs("/home/user/api_requests.log")
    expected_valid = {}
    expected_invalid = {}

    for request in source:
        request_id = request["request_id"]
        assert request_id not in expected_valid and request_id not in expected_invalid, "Duplicate request_id in source log."
        authorization = request["headers"]["Authorization"]
        assert authorization.startswith("Bearer ")
        token = authorization[len("Bearer "):]

        if signed_with_new_key(token):
            expected_valid[request_id] = request
        else:
            redacted = copy.deepcopy(request)
            redacted["headers"]["Authorization"] = "Bearer [REDACTED_CWE312]"
            expected_invalid[request_id] = redacted

    return source, expected_valid, expected_invalid


def index_predictions(records, label):
    indexed = {}
    for record in records:
        assert isinstance(record, dict), f"A {label} output record is not a JSON object."
        assert "request_id" in record, f"A {label} output record lacks request_id."
        request_id = record["request_id"]
        assert request_id not in indexed, f"Duplicate request_id {request_id!r} in {label} output."
        indexed[request_id] = record
    return indexed


def test_pyproject_toml_fixed():
    path = "/app/pyjwt-2.8.0/pyproject.toml"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert 'requires = ["flit_core >=3.2,<4.0"]' in content, "The syntax error in pyproject.toml was not fixed."


def test_vendored_pyjwt_installed():
    result = subprocess.run(
        ["python3", "-c", "import jwt; print(jwt.__version__)"],
        text=True,
        capture_output=True,
    )
    assert result.returncode == 0, f"PyJWT is not installed: {result.stderr}"
    assert result.stdout.strip() == "2.8.0", f"Expected PyJWT 2.8.0, got {result.stdout.strip()!r}."


def test_log_files_created():
    valid_path = "/home/user/valid_requests.log"
    invalid_path = "/home/user/invalid_requests.log"
    assert os.path.isfile(valid_path), f"Output file {valid_path} is missing."
    assert os.path.isfile(invalid_path), f"Output file {invalid_path} is missing."


def test_accuracy_metric():
    source, valid_gt, invalid_gt = expected_outputs()
    assert source, "The input log is empty or missing."

    valid_preds_list = load_logs("/home/user/valid_requests.log")
    invalid_preds_list = load_logs("/home/user/invalid_requests.log")
    valid_preds = index_predictions(valid_preds_list, "valid")
    invalid_preds = index_predictions(invalid_preds_list, "invalid")

    assert len(valid_preds_list) == len(valid_gt), "The valid output has the wrong number of records."
    assert len(invalid_preds_list) == len(invalid_gt), "The invalid output has the wrong number of records."
    assert set(valid_preds).isdisjoint(invalid_preds), "A request appears in both output files."

    correct = sum(valid_preds.get(k) == v for k, v in valid_gt.items())
    correct += sum(invalid_preds.get(k) == v for k, v in invalid_gt.items())
    accuracy = correct / len(source)
    assert accuracy >= 0.99, f"Accuracy {accuracy:.4f} is below the threshold of 0.99."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
