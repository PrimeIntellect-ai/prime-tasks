#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import subprocess
import importlib.machinery
import importlib.metadata
from collections import Counter

import pytest

TARGET_FILE = "/home/user/diagnostics.jsonl"
RAW_FILE = "/app/raw_logs.txt"
COLLECTOR = "/home/user/log_collector.py"
VENDORED_DIR = "/app/vendored/ujson-5.7.0"


@pytest.fixture(scope="session", autouse=True)
def run_collector_fresh():
    assert os.path.isfile(COLLECTOR), f"Collector script {COLLECTOR} does not exist."
    if os.path.exists(TARGET_FILE):
        os.remove(TARGET_FILE)

    try:
        result = subprocess.run(
            ["python3", COLLECTOR],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("log_collector.py did not finish within 180 seconds.")

    assert result.returncode == 0, (
        "log_collector.py failed when executed by the verifier.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def test_diagnostics_jsonl_valid_lines():
    target_file = TARGET_FILE
    assert os.path.isfile(target_file), f"Output file {target_file} does not exist. Did you run the script?"

    valid_lines = 0
    with open(target_file, "r") as f:
        for line in f:
            try:
                json.loads(line)
                valid_lines += 1
            except ValueError:
                pass

    threshold = 10000
    assert valid_lines >= threshold, (
        f"Expected at least {threshold} valid JSON lines in {target_file}, "
        f"but found {valid_lines}. The output might be corrupted due to race conditions or incomplete."
    )


def test_diagnostics_exactly_match_all_raw_logs():
    pristine_raw = [
        {
            "id": i,
            "level": "INFO",
            "message": "Diagnostic log entry",
            "payload": "x" * 50,
        }
        for i in range(10000)
    ]

    with open(RAW_FILE, "r", encoding="utf-8") as f:
        raw_lines = f.readlines()

    assert len(raw_lines) == 10000, "The raw input dataset was modified or truncated."
    parsed_raw = []
    for line_number, line in enumerate(raw_lines, 1):
        try:
            parsed_raw.append(json.loads(line))
        except Exception as exc:
            pytest.fail(f"Raw input line {line_number} is invalid JSON: {exc}")
    assert parsed_raw == pristine_raw, "The raw input dataset does not match the supplied 10,000 logs."

    expected = []
    for record in parsed_raw:
        processed = dict(record)
        processed["processed"] = True
        expected.append(processed)

    actual = []
    with open(TARGET_FILE, "r", encoding="utf-8") as f:
        for line_number, line in enumerate(f, 1):
            try:
                actual.append(json.loads(line))
            except Exception as exc:
                pytest.fail(f"Output line {line_number} is corrupted or invalid JSON: {exc}")

    assert len(actual) == len(expected), (
        f"Expected exactly {len(expected)} output records, but found {len(actual)}. "
        "Logs were dropped or duplicated."
    )

    canonical = lambda value: json.dumps(value, sort_keys=True, separators=(",", ":"))
    assert Counter(map(canonical, actual)) == Counter(map(canonical, expected)), (
        "Output records do not exactly match the raw logs with processed=true; "
        "one or more logs were altered, dropped, or duplicated."
    )


def test_ujson_installed():
    try:
        import ujson
    except ImportError:
        pytest.fail("ujson module could not be imported. The vendored package was not successfully installed.")

    try:
        res = ujson.loads('{"test": 1}')
        assert res == {"test": 1}
    except Exception as e:
        pytest.fail(f"ujson is installed but failed to parse a simple JSON string: {e}")

    module_path = os.path.realpath(ujson.__file__)
    vendored_path = os.path.realpath(VENDORED_DIR)
    assert os.path.commonpath([module_path, vendored_path]) == vendored_path, (
        f"Imported ujson from {module_path}, not from the repaired vendored source at {vendored_path}."
    )
    assert isinstance(ujson.__loader__, importlib.machinery.ExtensionFileLoader), (
        "The imported ujson is not the compiled extension from the vendored build."
    )
    assert importlib.metadata.version("ujson") == "5.7.0"

    source_path = os.path.join(VENDORED_DIR, "python", "ujson.c")
    with open(source_path, "r", encoding="utf-8") as f:
        source = f.read()
    assert "<Pythonn.h>" not in source, "The broken Python header include was not repaired."
    assert "PyMODINIT_FUNCC" not in source, "The broken module initializer declaration was not repaired."
    assert "<Python.h>" in source
    assert "PyMODINIT_FUNC" in source
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
