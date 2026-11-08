#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import json
import math
import os
import secrets
import shutil
import subprocess
import tempfile


def test_anomalies_json_exists_and_correct():
    output_path = "/home/user/output/anomalies.json"
    assert os.path.isfile(output_path), f"Expected output file {output_path} does not exist."

    with open(output_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {output_path} is not valid JSON."

    assert isinstance(results, list), f"Expected {output_path} to contain a JSON array."
    assert len(results) == 4, f"Expected 4 results in {output_path}, found {len(results)}."

    expected = {
        "event_1": 1.8394,
        "event_2": 6.0653,
        "event_3": 0.0,
        "event_4": 8.1873
    }

    actual = {item.get("event_id"): item.get("score") for item in results if isinstance(item, dict)}

    for event_id, expected_score in expected.items():
        assert event_id in actual, f"Missing {event_id} in {output_path}."
        actual_score = actual[event_id]
        assert isinstance(actual_score, (int, float)), f"Score for {event_id} is not a number."
        assert math.isclose(actual_score, expected_score, abs_tol=1e-4), \
            f"Score for {event_id} is incorrect. Expected ~{expected_score}, got {actual_score}."


def test_regression_script_exists_and_passes():
    script_path = "/home/user/system/test_regression.py"
    assert os.path.isfile(script_path), f"Regression test script {script_path} does not exist."

    result = subprocess.run(["python3", script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Regression test script failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"


def test_processor_script_runnable():
    processor_path = "/home/user/system/processor.py"
    assert os.path.isfile(processor_path), f"Processor script {processor_path} does not exist."

    result = subprocess.run(["python3", "-m", "py_compile", processor_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Processor script has syntax errors:\n{result.stderr}"


def test_processor_executes_on_derived_inputs():
    processor_path = "/home/user/system/processor.py"
    input_path = "/home/user/data/raw_events.jsonl"
    output_path = "/home/user/output/anomalies.json"

    nonce = secrets.token_hex(8)
    cases = []
    for i in range(7):
        x1 = secrets.randbelow(31) - 15
        y1 = secrets.randbelow(31) - 15
        if i == 2:
            x2, y2, delta = x1, y1, 0
        else:
            x2 = x1 + secrets.randbelow(9) + 1
            y2 = y1 - (secrets.randbelow(7) + 1)
            delta = 0 if i == 0 else secrets.randbelow(30) + 1
        cases.append((f"verify_{nonce}_{i}", x1, y1, x2, y2, delta,
                      "utf-16le" if i % 2 else "utf-8"))

    records = []
    expected = {}
    for event_id, x1, y1, x2, y2, delta, encoding in cases:
        payload_obj = {
            "p1": {"x": x1, "y": y1},
            "p2": {"x": x2, "y": y2},
            "time_delta": delta,
        }
        payload = base64.b64encode(json.dumps(payload_obj).encode(encoding)).decode("ascii")
        records.append({"event_id": event_id, "payload": payload})
        distance = math.sqrt((x1 - x2) ** 2 + (y1 - y2) ** 2)
        expected[event_id] = round(distance * math.exp(-0.1 * delta), 4)

    original_input = open(input_path, "rb").read()
    output_existed = os.path.exists(output_path)
    original_output = open(output_path, "rb").read() if output_existed else None

    try:
        with open(input_path, "w", encoding="utf-8") as f:
            for record in records:
                f.write(json.dumps(record) + "\n")
        if os.path.exists(output_path):
            os.remove(output_path)

        result = subprocess.run(
            ["python3", processor_path],
            cwd="/home/user/system",
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, \
            f"processor.py failed on verification inputs.\nStdout: {result.stdout}\nStderr: {result.stderr}"
        assert os.path.isfile(output_path), "processor.py did not create anomalies.json"

        with open(output_path, encoding="utf-8") as f:
            generated = json.load(f)
        assert isinstance(generated, list), "Generated anomalies.json is not a JSON array"
        assert len(generated) == len(records), \
            f"Processor emitted {len(generated)} records for {len(records)} inputs"

        actual = {}
        for item in generated:
            assert isinstance(item, dict), "Each generated result must be an object"
            assert "event_id" in item and "score" in item, "Generated result lacks event_id or score"
            assert item["event_id"] not in actual, f"Duplicate result for {item['event_id']}"
            assert isinstance(item["score"], (int, float)) and not isinstance(item["score"], bool)
            assert math.isfinite(item["score"]), f"Non-finite score for {item['event_id']}"
            actual[item["event_id"]] = item["score"]

        assert set(actual) == set(expected), "Processor omitted or invented event IDs"
        for event_id, expected_score in expected.items():
            assert math.isclose(actual[event_id], expected_score, rel_tol=0, abs_tol=1e-9), \
                f"Wrong derived score for {event_id}: expected {expected_score}, got {actual[event_id]}"
    finally:
        with open(input_path, "wb") as f:
            f.write(original_input)
        if output_existed:
            with open(output_path, "wb") as f:
                f.write(original_output)
        elif os.path.exists(output_path):
            os.remove(output_path)


def _run_regression_against(module_source):
    script_path = "/home/user/system/test_regression.py"
    with tempfile.TemporaryDirectory() as sandbox:
        shutil.copy2(script_path, os.path.join(sandbox, "test_regression.py"))
        with open(os.path.join(sandbox, "processor.py"), "w", encoding="utf-8") as f:
            f.write(module_source)
        env = os.environ.copy()
        env["PYTHONPATH"] = sandbox
        return subprocess.run(
            ["python3", "-m", "pytest", "-q", "test_regression.py"],
            cwd=sandbox,
            env=env,
            capture_output=True,
            text=True,
            timeout=20,
        )


def test_regression_script_exercises_both_regressions():
    script_path = "/home/user/system/test_regression.py"
    source = open(script_path, encoding="utf-8").read()
    tree = ast.parse(source, filename=script_path)
    imports_processor = any(
        (isinstance(node, ast.Import) and any(alias.name == "processor" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "processor")
        for node in ast.walk(tree)
    )
    assert imports_processor, "Regression script must import processor"

    utf16_bug = '''
import base64, json, math

def decode_payload(b64_str):
    raw = base64.b64decode(b64_str)
    return json.loads(raw.decode("utf-8"))

def compute_score(p1, p2, time_delta):
    return math.hypot(p1["x"] - p2["x"], p1["y"] - p2["y"]) * math.exp(-0.1 * time_delta)
'''
    zero_delta_bug = '''
import base64, json, math

def decode_payload(b64_str):
    raw = base64.b64decode(b64_str)
    for encoding in ("utf-8", "utf-16le"):
        try:
            return json.loads(raw.decode(encoding))
        except (UnicodeDecodeError, json.JSONDecodeError):
            pass
    raise ValueError("bad payload")

def compute_score(p1, p2, time_delta):
    if time_delta == 0:
        raise ZeroDivisionError("zero time delta")
    return math.hypot(p1["x"] - p2["x"], p1["y"] - p2["y"]) * math.exp(-0.1 * time_delta)
'''

    utf16_result = _run_regression_against(utf16_bug)
    assert utf16_result.returncode != 0, \
        "Regression script does not detect the utf-16le deserialization regression"

    zero_result = _run_regression_against(zero_delta_bug)
    assert zero_result.returncode != 0, \
        "Regression script does not detect the zero-time-delta regression"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
