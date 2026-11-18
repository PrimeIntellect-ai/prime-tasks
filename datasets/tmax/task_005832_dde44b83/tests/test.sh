#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import ast
import contextlib
import importlib.util
import io
import math
import os
import re
import subprocess


def test_api_key_extracted():
    mem_file = "/home/user/app/crash_mem.bin"
    assert os.path.isfile(mem_file), f"The memory dump file {mem_file} is missing."

    with open(mem_file, "rb") as f:
        content = f.read()

    # Dynamically find the expected key from the binary file
    match = re.search(b"API_KEY=([a-zA-Z0-9]{16})", content)
    assert match is not None, "Could not find API_KEY in crash_mem.bin"
    expected_key = match.group(1).decode("utf-8")

    solution_file = "/home/user/solution/api_key.txt"
    assert os.path.isfile(solution_file), f"Solution file {solution_file} was not created."

    with open(solution_file, "r", encoding="utf-8") as f:
        actual_key = f.read().strip()

    assert actual_key == expected_key, f"Expected API key '{expected_key}', but found '{actual_key}' in {solution_file}"


def test_report_py_fixed():
    report_file = "/home/user/app/report.py"
    assert os.path.isfile(report_file), f"The Python script {report_file} is missing."

    with open(report_file, "r", encoding="utf-8") as f:
        content = f.read()

    assert "math.isclose" in content, "The report.py file does not appear to use math.isclose() as requested."

    # Run the script and check output
    result = subprocess.run(["python3", report_file], capture_output=True, text=True)

    assert result.returncode == 0, f"report.py crashed or returned non-zero exit code: {result.stderr}"

    output = result.stdout.strip()
    assert output == "REPORT_VALID", f"Expected script to output 'REPORT_VALID', but got '{output}'"

    # Ensure math.isclose() is actually used as part of an if-condition, rather
    # than merely appearing in a comment or unused expression.
    tree = ast.parse(content, filename=report_file)
    conditional_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.If):
            for child in ast.walk(node.test):
                if (
                    isinstance(child, ast.Call)
                    and isinstance(child.func, ast.Attribute)
                    and child.func.attr == "isclose"
                    and isinstance(child.func.value, ast.Name)
                    and child.func.value.id == "math"
                ):
                    conditional_calls.append(child)

    assert conditional_calls, "math.isclose() must be used in the report's conditional comparison."
    assert any(len(call.args) == 2 and not call.keywords for call in conditional_calls), \
        "math.isclose() must compare two values using its default tolerances."

    spec = importlib.util.spec_from_file_location("submitted_report", report_file)
    assert spec is not None and spec.loader is not None, "Could not load report.py"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "generate_report", None)), "report.py must retain a callable generate_report()."
    assert getattr(module, "math", None) is math, "report.py must use Python's math module."

    original_isclose = math.isclose
    expected_pair = (0.1 + 0.2, 0.3)

    def run_with_isclose_result(forced_result):
        calls = []

        def recording_isclose(*args, **kwargs):
            calls.append((args, kwargs))
            return forced_result

        module.math.isclose = recording_isclose
        captured = io.StringIO()
        try:
            with contextlib.redirect_stdout(captured):
                module.generate_report()
        finally:
            module.math.isclose = original_isclose
        return captured.getvalue().strip(), calls

    true_output, true_calls = run_with_isclose_result(True)
    false_output, false_calls = run_with_isclose_result(False)

    def has_expected_default_call(calls):
        for args, kwargs in calls:
            if kwargs or len(args) != 2:
                continue
            if args == expected_pair or args == expected_pair[::-1]:
                return True
        return False

    assert has_expected_default_call(true_calls), \
        "generate_report() did not call math.isclose() on the computed sum and expected total using default tolerances."
    assert has_expected_default_call(false_calls), \
        "generate_report() did not consistently use math.isclose() for the report comparison."
    assert true_output == "REPORT_VALID", \
        f"Expected REPORT_VALID when math.isclose() succeeds, but got '{true_output}'"
    assert false_output != "REPORT_VALID", \
        "REPORT_VALID was printed even when math.isclose() was forced to fail."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
