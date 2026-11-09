#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import sys

import pytest
import requests

BUG_FILE = '/home/user/isolated_bug.txt'
LOG_FILE = '/home/user/app/data/massive_log.txt'
PARSER_FILE = '/home/user/app/backend/parser.py'
GATEWAY_URL = 'http://localhost:5000/process_logs'


def test_isolated_bug_file():
    assert os.path.isfile(BUG_FILE), f"The isolated bug file {BUG_FILE} does not exist."

    with open(BUG_FILE, 'r') as f:
        content = f.read().strip()

    # Preserve the original assertion.
    expected_line = "[ERROR] [System] [Auth Missing closing bracket"
    assert content == expected_line, f"The isolated bug file contains '{content}' instead of the expected '{expected_line}'."

    # Derive the toxic line from the supplied batch and verify it is the unique
    # bracket-malformed line, rather than trusting only the known literal.
    assert os.path.isfile(LOG_FILE), f"The source log batch {LOG_FILE} is missing."
    with open(LOG_FILE, 'r') as f:
        lines = [line.rstrip('\r\n') for line in f]
    assert len(lines) == 5000, f"Expected 5000 source log lines, found {len(lines)}."
    malformed = [line for line in lines if line.lstrip().startswith('[') and line.count('[') != line.count(']')]
    assert len(malformed) == 1, f"Expected one uniquely malformed line in the source batch, found {len(malformed)}."
    assert content == malformed[0], "isolated_bug.txt is not the unique malformed line derived from massive_log.txt."


def run_parser(cases):
    assert os.path.isfile(PARSER_FILE), f"The required parser artifact {PARSER_FILE} does not exist."
    assert not os.path.islink(PARSER_FILE), f"The parser artifact {PARSER_FILE} must be a regular source file, not a symlink."

    runner = r'''
import importlib.util
import json
import sys

path = sys.argv[1]
spec = importlib.util.spec_from_file_location("submitted_parser", path)
if spec is None or spec.loader is None:
    raise RuntimeError("Could not load parser.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
if not callable(getattr(module, "parse_log", None)):
    raise RuntimeError("parser.py does not define a callable parse_log")
cases = json.load(sys.stdin)
json.dump([module.parse_log(value) for value in cases], sys.stdout)
'''
    try:
        proc = subprocess.run(
            [sys.executable, '-I', '-c', runner, PARSER_FILE],
            input=json.dumps(cases),
            text=True,
            capture_output=True,
            timeout=3,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('Executing parse_log from parser.py hung on malformed input.')

    assert proc.returncode == 0, f"Executing parser.py failed: {proc.stderr}"
    try:
        return json.loads(proc.stdout)
    except (ValueError, TypeError) as exc:
        pytest.fail(f"parser.py did not produce valid results when executed: {exc}; output={proc.stdout!r}")


def test_parser_artifact_handles_generated_inputs_without_hanging():
    token = secrets.token_hex(16)
    cases = [
        f"  Plain-{token}  ",
        f"[INFO] Normal-{token}",
        f"[{token}",
        f"[ERROR] [{token}",
        f"[ERROR] [System] [Auth-{token} missing closing bracket",
    ]
    expected = [
        f"Plain-{token}",
        f"Normal-{token}",
        "malformed",
        "malformed",
        "malformed",
    ]
    assert run_parser(cases) == expected


def test_process_logs_endpoint():
    payload = {
        "logs": [
            "[INFO] Normal log",
            "[ERROR] [System] [Auth Missing closing bracket"
        ]
    }

    try:
        response = requests.post(GATEWAY_URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API Gateway at {GATEWAY_URL}. Error: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    # Preserve the original service assertion.
    expected_results = ["Normal log", "malformed"]
    assert "results" in data, f"Response JSON missing 'results' key. Data: {data}"
    assert data["results"] == expected_results, f"Expected results {expected_results}, but got {data['results']}."


def test_process_logs_endpoint_with_generated_payload():
    token = secrets.token_hex(16)
    payload = {
        "logs": [
            f"[INFO] Event-{token}",
            f"[WARN] [Subsystem] [{token} unterminated",
            f"Plain-{token}",
            f"[{token}",
        ]
    }
    expected = [f"Event-{token}", "malformed", f"Plain-{token}", "malformed"]

    try:
        response = requests.post(GATEWAY_URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Generated request to the API Gateway failed or hung: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 for generated payload, got {response.status_code}: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Generated response is not valid JSON: {response.text}")
    assert data.get("results") == expected, f"Expected generated results {expected}, got {data}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
