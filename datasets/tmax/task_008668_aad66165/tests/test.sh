#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import random
import string
import subprocess
import sys
import threading
import pytest

SECRET_FILE = "/home/user/secret.txt"
PARSER_FILE = "/home/user/ticket_4099/parser.py"
EXPECTED_SECRET = "sk_bkp_8f92a1b7c6d5e4f3g2h1i0j"


def test_secret_recovered():
    assert os.path.exists(SECRET_FILE), f"Secret file {SECRET_FILE} does not exist."
    with open(SECRET_FILE, "r") as f:
        content = f.read().strip()
    assert EXPECTED_SECRET in content, f"The recovered secret in {SECRET_FILE} is incorrect."


def test_parser_exists():
    assert os.path.isfile(PARSER_FILE), f"Parser file {PARSER_FILE} does not exist."


def test_parser_fixed():
    spec = importlib.util.spec_from_file_location("parser", PARSER_FILE)
    assert spec is not None, "Could not load parser spec."
    parser_module = importlib.util.module_from_spec(spec)
    sys.modules["parser"] = parser_module
    try:
        spec.loader.exec_module(parser_module)
    except Exception as e:
        pytest.fail(f"Failed to import {PARSER_FILE}: {e}")

    assert hasattr(parser_module, "extract_tags"), "extract_tags function missing in parser.py."
    extract_tags = parser_module.extract_tags

    try:
        valid_result = extract_tags("[WARN] [DB] Timeout")
    except Exception as e:
        pytest.fail(f"extract_tags raised an exception on valid input: {e}")

    assert valid_result == ["WARN", "DB"], f"extract_tags returned {valid_result} instead of ['WARN', 'DB'] on valid input."

    result_container = {}

    def run_malformed():
        try:
            extract_tags("[ERROR] Unclosed bracket [")
            result_container['status'] = 'no_exception'
        except ValueError as e:
            if str(e) == "Malformed input":
                result_container['status'] = 'success'
            else:
                result_container['status'] = f'wrong_value_error: {e}'
        except Exception as e:
            result_container['status'] = f'wrong_exception: {type(e).__name__}'

    t = threading.Thread(target=run_malformed)
    t.daemon = True
    t.start()
    t.join(timeout=2.0)

    if t.is_alive():
        pytest.fail("extract_tags entered an infinite loop on malformed input (missing ']').")

    status = result_container.get('status', 'unknown')
    assert status == 'success', f"extract_tags failed on malformed input. Expected ValueError('Malformed input'), got: {status}"


def test_parser_general_behavior():
    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + "_-.: "

    def token(min_len=0, max_len=18):
        return ''.join(rng.choice(alphabet) for _ in range(rng.randint(min_len, max_len)))

    cases = [
        {"kind": "valid", "input": "", "expected": []},
        {"kind": "valid", "input": "plain log text", "expected": []},
        {"kind": "valid", "input": "before [] after", "expected": [""]},
        {"kind": "valid", "input": "] stray close [ONE] tail", "expected": ["ONE"]},
        {"kind": "malformed", "input": "["},
        {"kind": "malformed", "input": "prefix [OK] suffix [unfinished"},
    ]

    for _ in range(30):
        expected = [token() for _ in range(rng.randint(1, 6))]
        parts = [token()]
        for tag in expected:
            parts.extend(("[", tag, "]", token()))
        cases.append({"kind": "valid", "input": ''.join(parts), "expected": expected})

    for _ in range(20):
        completed = [token() for _ in range(rng.randint(0, 4))]
        parts = [token()]
        for tag in completed:
            parts.extend(("[", tag, "]", token()))
        parts.extend(("[", token()))
        cases.append({"kind": "malformed", "input": ''.join(parts)})

    runner = r'''
import importlib.util
import json
import sys

parser_path = sys.argv[1]
cases = json.loads(sys.stdin.read())
spec = importlib.util.spec_from_file_location("submitted_parser", parser_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
if not hasattr(module, "extract_tags"):
    raise AssertionError("extract_tags function missing")

results = []
for case in cases:
    try:
        value = module.extract_tags(case["input"])
        results.append({"status": "returned", "value": value})
    except ValueError as exc:
        results.append({"status": "value_error", "message": str(exc)})
    except BaseException as exc:
        results.append({"status": "other_exception", "type": type(exc).__name__, "message": str(exc)})
print("RESULT_JSON:" + json.dumps(results))
'''

    try:
        completed = subprocess.run(
            [sys.executable, "-c", runner, PARSER_FILE],
            input=json.dumps(cases),
            text=True,
            capture_output=True,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("extract_tags did not terminate while exercising varied inputs.")

    assert completed.returncode == 0, (
        "parser failed during varied-input tests: " + completed.stderr
    )
    result_lines = [line for line in completed.stdout.splitlines() if line.startswith("RESULT_JSON:")]
    assert result_lines, "Parser test runner did not produce results."
    results = json.loads(result_lines[-1][len("RESULT_JSON:"):])
    assert len(results) == len(cases)

    for case, result in zip(cases, results):
        if case["kind"] == "valid":
            assert result == {"status": "returned", "value": case["expected"]}, (
                f"extract_tags failed for valid input {case['input']!r}: {result}"
            )
        else:
            assert result == {"status": "value_error", "message": "Malformed input"}, (
                f"extract_tags did not raise ValueError('Malformed input') for "
                f"unclosed bracket input {case['input']!r}: {result}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
