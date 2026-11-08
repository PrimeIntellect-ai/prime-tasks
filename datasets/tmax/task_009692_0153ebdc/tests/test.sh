#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import collections
import json
import os
import re
import subprocess
import textwrap
import pytest

PARSER_PATH = "/home/user/suspicious_parser.py"
OUTPUT_PATH = "/home/user/parsed_output.json"
SAMPLE_PATH = "/home/user/sample.log"
TEST_PATH = "/home/user/test_parser.py"


def expected_from_sample():
    expected = []
    with open(SAMPLE_PATH, "r") as f:
        for raw_line in f:
            line = raw_line.strip()
            if line.startswith("FORMAT_V1:"):
                expected.append({"version": "v1", "data": line.split(":", 1)[1].strip()})
            elif line.startswith("FORMAT_V2:"):
                expected.append({"version": "v2", "data": line.split(":", 1)[1].strip()})
    return expected


def assert_correct_records(data):
    expected = expected_from_sample()
    assert isinstance(data, list), "Parsed output should be a JSON list."
    assert len(data) == 9, f"Expected 9 parsed items in the JSON output, found {len(data)}."

    for i, item in enumerate(data):
        assert "version" in item, f"Missing 'version' key in parsed item at index {i}."
        assert "data" in item, f"Missing 'data' key in parsed item at index {i}."
        assert item["version"] in ["v1", "v2"], f"Invalid version value in parsed item at index {i}."
        assert isinstance(item, dict) and set(item) == {"version", "data"}, (
            f"Parsed item at index {i} has an incorrect JSON structure."
        )

    actual_records = collections.Counter((item["version"], item["data"]) for item in data)
    expected_records = collections.Counter((item["version"], item["data"]) for item in expected)
    assert actual_records == expected_records, "parsed_output.json does not contain the records from sample.log."


def test_parsed_output():
    output_path = OUTPUT_PATH
    assert os.path.exists(output_path), f"{output_path} does not exist. Ensure the script was run and generated the output."

    with open(output_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{output_path} is not valid JSON.")

    assert_correct_records(data)


def test_regression_script_execution():
    script_path = TEST_PATH
    assert os.path.exists(script_path), f"{script_path} does not exist. You must write a regression test."

    try:
        result = subprocess.run(["python3", script_path], capture_output=True, text=True, timeout=10)
    except subprocess.TimeoutExpired:
        pytest.fail("test_parser.py hung instead of completing successfully.")
    assert result.returncode == 0, (
        f"test_parser.py failed to execute successfully (exit code {result.returncode}).\n"
        f"STDOUT:\n{result.stdout}\n"
        f"STDERR:\n{result.stderr}"
    )


def test_regression_script_is_real_unittest():
    with open(TEST_PATH, "r") as f:
        source = f.read()
    tree = ast.parse(source, filename=TEST_PATH)

    imports_unittest = any(
        (isinstance(node, ast.Import) and any(alias.name == "unittest" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "unittest")
        for node in ast.walk(tree)
    )
    imports_parser = any(
        (isinstance(node, ast.Import) and any(alias.name == "suspicious_parser" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "suspicious_parser")
        for node in ast.walk(tree)
    )
    test_methods = [
        node for node in ast.walk(tree)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test")
    ]
    test_case_classes = [
        node for node in ast.walk(tree) if isinstance(node, ast.ClassDef) and any(
            (isinstance(base, ast.Attribute) and base.attr == "TestCase")
            or (isinstance(base, ast.Name) and base.id == "TestCase")
            for base in node.bases
        )
    ]
    assertion_calls = [
        node for node in ast.walk(tree) if isinstance(node, ast.Call) and (
            (isinstance(node.func, ast.Attribute) and node.func.attr.startswith("assert"))
            or (isinstance(node.func, ast.Name) and node.func.id.startswith("assert"))
        )
    ]

    assert imports_unittest, "test_parser.py must use the standard unittest framework."
    assert imports_parser, "test_parser.py must import the processing code from suspicious_parser.py."
    assert test_case_classes and test_methods, "test_parser.py must define at least one unittest test case."
    assert assertion_calls, "test_parser.py must make assertions about parser behavior."
    assert "FORMAT_V1:" in source and "FORMAT_V2:" in source, (
        "The regression test must exercise the opposing-format edge-case lines."
    )

    try:
        result = subprocess.run(
            ["python3", "-m", "unittest", TEST_PATH], capture_output=True, text=True, timeout=10
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The unittest regression suite hung.")
    combined = result.stdout + result.stderr
    assert result.returncode == 0, f"unittest failed:\n{combined}"
    match = re.search(r"Ran\s+(\d+)\s+tests?", combined)
    assert match and int(match.group(1)) >= 1, "No unittest regression tests were actually run."


def test_parser_retains_multithreaded_processing():
    assert os.path.exists(PARSER_PATH), f"{PARSER_PATH} does not exist."
    with open(PARSER_PATH, "r") as f:
        tree = ast.parse(f.read(), filename=PARSER_PATH)

    main_functions = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == "main"]
    assert main_functions, "suspicious_parser.py must retain its main processing function."
    main = main_functions[0]
    executor_calls = [
        n for n in ast.walk(main) if isinstance(n, ast.Call)
        and ((isinstance(n.func, ast.Attribute) and n.func.attr == "ThreadPoolExecutor")
             or (isinstance(n.func, ast.Name) and n.func.id == "ThreadPoolExecutor"))
    ]
    assert executor_calls, "The parser must still use ThreadPoolExecutor rather than being single-threaded."
    for call in executor_calls:
        for keyword in call.keywords:
            if keyword.arg == "max_workers" and isinstance(keyword.value, ast.Constant) and isinstance(keyword.value.value, int):
                assert keyword.value.value > 1, "The concurrency bug may not be bypassed with a single worker."

    parallel_dispatch = [
        n for n in ast.walk(main) if isinstance(n, ast.Call)
        and isinstance(n.func, ast.Attribute) and n.func.attr in {"map", "submit"}
        and any(isinstance(arg, ast.Name) and arg.id == "parse_line" for arg in n.args)
    ]
    assert parallel_dispatch, "main() must dispatch parse_line through the thread pool."


def test_processing_function_concurrent_edge_case():
    harness = textwrap.dedent(r'''
        import collections
        import concurrent.futures
        import importlib.util

        spec = importlib.util.spec_from_file_location("submission_parser", "/home/user/suspicious_parser.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        assert callable(getattr(module, "parse_line", None))
        assert isinstance(getattr(module, "parsed_results", None), list)
        module.parsed_results.clear()

        lines = []
        expected = []
        for i in range(60):
            lines.append(f"FORMAT_V1: v1-edge-{i}")
            expected.append(("v1", f"v1-edge-{i}"))
            lines.append(f"FORMAT_V2: v2-edge-{i}")
            expected.append(("v2", f"v2-edge-{i}"))

        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            list(executor.map(module.parse_line, lines))

        actual = module.parsed_results
        assert len(actual) == len(expected), (len(actual), len(expected))
        assert all(isinstance(x, dict) and set(x) == {"version", "data"} for x in actual)
        assert collections.Counter((x["version"], x["data"]) for x in actual) == collections.Counter(expected)
    ''')
    try:
        result = subprocess.run(["python3", "-c", harness], capture_output=True, text=True, timeout=5)
    except subprocess.TimeoutExpired:
        pytest.fail("Concurrent mixed FORMAT_V1/FORMAT_V2 processing deadlocked.")
    assert result.returncode == 0, (
        "parse_line did not correctly process concurrent edge-case records.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


def test_suspicious_parser_execution_no_deadlock():
    script_path = PARSER_PATH
    assert os.path.exists(script_path), f"{script_path} does not exist."

    if os.path.exists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)
    try:
        result = subprocess.run(["python3", script_path], capture_output=True, text=True, timeout=5)
        assert result.returncode == 0, (
            f"suspicious_parser.py failed to execute (exit code {result.returncode}).\n"
            f"STDOUT:\n{result.stdout}\n"
            f"STDERR:\n{result.stderr}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail("suspicious_parser.py timed out after 5 seconds. The deadlock issue is likely not resolved.")

    assert os.path.exists(OUTPUT_PATH), "Running suspicious_parser.py did not generate parsed_output.json."
    with open(OUTPUT_PATH, "r") as f:
        assert_correct_records(json.load(f))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
