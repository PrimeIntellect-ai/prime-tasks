#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import subprocess
import sys
from pathlib import Path

APP = Path("/home/user/app")
DATA = APP / "data/system.log"
SUMMARY = APP / "final_summary.json"
SKIPPED = APP / "skipped.log"


def run_processor(timeout=15):
    script = APP / "process_logs.py"
    assert script.is_file(), f"{script} does not exist."
    result = subprocess.run(
        [sys.executable, str(script)], cwd=str(APP), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout
    )
    assert result.returncode == 0, (
        f"process_logs.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_processor_executes_on_derived_input_and_handles_exceptions():
    original_data = DATA.read_bytes()
    token = os.urandom(6).hex()
    count_500 = random.SystemRandom().randint(3, 8)

    records = []
    for i in range(count_500):
        records.append({
            "status": 500 if i % 2 == 0 else "500",
            "endpoint": f"api/v2/{token}/{i}",
            "method": "GET",
            "user_agent": "verifier",
        })
    records.extend([
        {"status": 200, "endpoint": f"api/v1/legacy/{token}/ok1", "method": "GET", "user_agent": "verifier"},
        {"status": 201, "endpoint": f"api/v1/legacy/{token}/ok2", "method": "GET", "user_agent": "verifier"},
        {"status": 200, "endpoint": f"api/v2/{token}/ordinary", "method": "GET"},
    ])
    value_record = {"status": 200, "endpoint": f"api/v1/legacy/{token}/bad", "method": "GET"}
    memory_record = {"status": 200, "endpoint": f"api/v2/{token}/large", "method": "POST", "payload_size": 10001, "user_agent": "verifier"}
    records.extend([value_record, memory_record])
    random.SystemRandom().shuffle(records)

    raw_lines = [json.dumps(record, separators=(",", ":")) for record in records]
    expected_skipped = {
        json.dumps(value_record, separators=(",", ":")) + "\n",
        json.dumps(memory_record, separators=(",", ":")) + "\n",
    }

    try:
        DATA.write_text("".join(line + "\n" for line in raw_lines))
        SUMMARY.unlink(missing_ok=True)
        SKIPPED.unlink(missing_ok=True)
        run_processor()

        assert SUMMARY.is_file(), "Executing process_logs.py did not create final_summary.json."
        with SUMMARY.open() as f:
            summary = json.load(f)
        assert summary.get("500_count") == count_500, (
            f"Derived input expected {count_500} 500 responses, got {summary.get('500_count')}."
        )
        assert summary.get("legacy_hits") == 2, (
            f"Derived input expected 2 successfully processed legacy hits, got {summary.get('legacy_hits')}."
        )

        assert SKIPPED.is_file(), "Executing process_logs.py did not create skipped.log."
        skipped_lines = set(SKIPPED.read_text().splitlines(keepends=True))
        for expected in expected_skipped:
            assert expected in skipped_lines, f"skipped.log is missing the exact raw line {expected!r}"
    finally:
        DATA.write_bytes(original_data)
        SUMMARY.unlink(missing_ok=True)
        SKIPPED.unlink(missing_ok=True)


def test_run_processor_on_provided_log():
    SUMMARY.unlink(missing_ok=True)
    SKIPPED.unlink(missing_ok=True)
    run_processor()


def test_final_summary_exists_and_correct():
    summary_path = "/home/user/app/final_summary.json"
    assert os.path.isfile(summary_path), f"{summary_path} does not exist. Did you run the fixed script?"

    with open(summary_path, "r") as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{summary_path} does not contain valid JSON."

    assert "500_count" in summary, "final_summary.json is missing the '500_count' key."
    # There are exactly 6 logs with status 500 or "500" in the provided system.log
    assert summary["500_count"] == 6, f"Expected 500_count to be 6, but got {summary['500_count']}. Make sure both integer and string 500s are counted."


def test_skipped_log_exists_and_contains_exceptions():
    skipped_path = "/home/user/app/skipped.log"
    assert os.path.isfile(skipped_path), f"{skipped_path} does not exist. Did you catch the exceptions and write to it?"

    with open(skipped_path, "r") as f:
        content = f.read().strip().split('\n')

    value_error_line = '{"status": 200, "endpoint": "api/v1/legacy", "method": "GET"}'
    memory_error_line = '{"status": 200, "endpoint": "api/v2/users", "method": "POST", "payload_size": 15000, "user_agent": "test"}'

    # Strip whitespace from both sides for robust comparison
    cleaned_content = [line.strip() for line in content if line.strip()]

    assert value_error_line in cleaned_content, f"skipped.log is missing the line that triggers ValueError: {value_error_line}"
    assert memory_error_line in cleaned_content, f"skipped.log is missing the line that triggers MemoryError: {memory_error_line}"


def test_fuzzer_and_regression_tests_exist_and_are_functional():
    fuzzer_path = APP / "fuzzer.py"
    regression_path = APP / "test_regression.py"

    assert fuzzer_path.is_file(), f"{fuzzer_path} does not exist. You must create the fuzzing script."
    assert regression_path.is_file(), f"{regression_path} does not exist. You must create the regression test file."

    fuzzer_source = fuzzer_path.read_text()
    try:
        fuzzer_tree = ast.parse(fuzzer_source, str(fuzzer_path))
    except SyntaxError as exc:
        assert False, f"fuzzer.py is not valid Python: {exc}"
    assert any(
        isinstance(node, ast.Call) and (
            (isinstance(node.func, ast.Name) and node.func.id == "process_line") or
            (isinstance(node.func, ast.Attribute) and node.func.attr == "process_line")
        )
        for node in ast.walk(fuzzer_tree)
    ), "fuzzer.py must feed generated inputs to process_line(data)."
    assert any(
        (isinstance(node, ast.Import) and any(alias.name == "random" for alias in node.names)) or
        (isinstance(node, ast.ImportFrom) and node.module == "random")
        for node in ast.walk(fuzzer_tree)
    ), "fuzzer.py must generate randomized inputs."

    fuzz_result = subprocess.run(
        [sys.executable, str(fuzzer_path)], cwd=str(APP), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert fuzz_result.returncode == 0, (
        f"fuzzer.py is not functional (exit {fuzz_result.returncode}).\n"
        f"stdout:\n{fuzz_result.stdout}\nstderr:\n{fuzz_result.stderr}"
    )

    regression_source = regression_path.read_text()
    try:
        regression_tree = ast.parse(regression_source, str(regression_path))
    except SyntaxError as exc:
        assert False, f"test_regression.py is not valid Python: {exc}"
    test_functions = [
        node for node in ast.walk(regression_tree)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test")
    ]
    assert test_functions, "test_regression.py must contain at least one unittest test method."
    assert any(
        isinstance(node, ast.Call) and (
            (isinstance(node.func, ast.Name) and node.func.id == "process_line") or
            (isinstance(node.func, ast.Attribute) and node.func.attr == "process_line")
        )
        for node in ast.walk(regression_tree)
    ), "test_regression.py must exercise process_line."
    constants = [node.value for node in ast.walk(regression_tree) if isinstance(node, ast.Constant)]
    assert "500" in constants, 'test_regression.py must test the string "500" status.'
    assert any(isinstance(value, str) and "legacy" in value for value in constants), (
        "test_regression.py must test the first legacy-endpoint crash condition."
    )
    assertion_count = sum(
        isinstance(node, ast.Assert) or
        (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr.startswith("assert"))
        for node in ast.walk(regression_tree)
    )
    assert assertion_count >= 2, "test_regression.py must assert both required regression behaviors."

    regression_result = subprocess.run(
        [sys.executable, "-m", "unittest", "-v", "test_regression.py"],
        cwd=str(APP), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert regression_result.returncode == 0, (
        f"Regression tests failed.\nstdout:\n{regression_result.stdout}\n"
        f"stderr:\n{regression_result.stderr}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
