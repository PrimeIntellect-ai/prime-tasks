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
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import math
import os

import pytest
import requests

CANONICAL_LOGS = [
    {"id": 1, "lang": "en", "message": "Login failed", "x": 1.0, "y": 2.0},
    {"id": 2, "lang": "ja", "message": "ログイン失敗", "x": 10.0, "y": 10.0},
    {"id": 3, "lang": "ar", "message": "فشل الدخول", "x": 5.0, "y": 12.0},
    {"id": 4, "lang": "en", "message": "Timeout", "x": 0.0, "y": 0.0},
    {"id": 5, "lang": "en", "message": "Error", "x": 1.0, "y": 1.0},
    {"id": 6, "lang": "en", "message": "Crash", "x": 2.0, "y": 2.0},
    {"id": 7, "lang": "en", "message": "Warning", "x": 3.0, "y": 3.0},
    {"id": 8, "lang": "en", "message": "Info", "x": 4.0, "y": 4.0},
    {"id": 9, "lang": "ja", "message": "エラー", "x": 20.0, "y": 21.0},
    {"id": 10, "lang": "ja", "message": "警告", "x": 0.0, "y": 1.0},
    {"id": 11, "lang": "ja", "message": "情報", "x": 0.0, "y": 2.0},
    {"id": 12, "lang": "ja", "message": "システム", "x": 0.0, "y": 3.0},
]


def test_parser_bug_fixed():
    path = "/app/vendored/pylogcalc-0.1.0/pylogcalc/parser.py"
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "msg.encode('ascii')" not in content, "The bug (forcing ascii encoding) is still present in parser.py"
    assert (
        "msg.encode('utf-8')" in content
        or 'msg.encode("utf-8")' in content
        or "msg.encode('utf8')" in content
        or 'msg.encode("utf8")' in content
    ), "The encoding was not changed to utf-8 in parser.py"

    # Load and execute the submitted parser directly, rather than relying only
    # on source-text inspection or on a potentially stale installed copy.
    spec = importlib.util.spec_from_file_location("submitted_pylogcalc_parser", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    test_log = {"id": 999, "lang": "test", "message": "é雪", "x": 3.0, "y": 4.0}
    expected = 5.0 + len("é雪".encode("utf-8")) * 0.1
    actual = module.calculate_risk(test_log)
    assert isinstance(actual, float), "calculate_risk must return a float"
    assert math.isclose(actual, expected, rel_tol=0.0, abs_tol=1e-12), (
        f"calculate_risk returned {actual}, expected {expected} for UTF-8 input"
    )


def test_api_endpoint_returns_correct_data():
    logs_path = "/home/user/logs.jsonl"
    assert os.path.isfile(logs_path), f"File missing: {logs_path}"

    with open(logs_path, "r", encoding="utf-8") as f:
        actual_logs = [json.loads(line) for line in f if line.strip()]
    assert actual_logs == CANONICAL_LOGS, "The supplied logs.jsonl dataset was modified"

    # Derive the expected response from an immutable verifier-owned copy of the
    # supplied dataset, not from the world-writable agent file.
    logs = [dict(log) for log in CANONICAL_LOGS]
    lang_counts = {}
    sampled_logs = []
    for log in sorted(logs, key=lambda item: item["id"]):
        lang = log["lang"]
        if lang_counts.get(lang, 0) < 5:
            sampled_logs.append(log)
            lang_counts[lang] = lang_counts.get(lang, 0) + 1

    for log in sampled_logs:
        distance = math.sqrt(log["x"] ** 2 + log["y"] ** 2)
        log["risk"] = distance + len(log["message"].encode("utf-8")) * 0.1

    sampled_logs.sort(key=lambda item: (-item["risk"], item["id"]))
    expected_response = {
        "status": "success",
        "top_anomalies": [
            {"rank": rank, "id": log["id"], "risk": round(log["risk"], 2)}
            for rank, log in enumerate(sampled_logs[:3], start=1)
        ],
    }

    try:
        response = requests.get("http://127.0.0.1:9000/api/anomalies", timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the HTTP API at 127.0.0.1:9000/api/anomalies: {exc}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    assert "application/json" in response.headers.get("Content-Type", ""), "Expected Content-Type: application/json"

    try:
        actual_response = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert actual_response == expected_response, (
        f"API response {actual_response} does not match expected {expected_response}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
