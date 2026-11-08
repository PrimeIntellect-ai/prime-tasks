#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import subprocess
import sys

WORKSPACE = "/home/user/workspace"
DP_PATH = os.path.join(WORKSPACE, "data_processor.py")
PERF_PATH = os.path.join(WORKSPACE, "test_perf.py")
LOG_PATH = os.path.join(WORKSPACE, "success.log")

EXPECTED_PERF = b'''import time
import sys
import os

# Ensure we can import data_processor
sys.path.append('/home/user/workspace')
from data_processor import get_unique_elements

def test_performance():
    data = list(range(50000)) + list(range(10000))
    start = time.time()
    res = get_unique_elements(data)
    duration = time.time() - start

    assert len(res) == 50000, f"Expected 50000 unique elements, got {len(res)}"

    if duration > 1.0:
        print(f"FAIL: Too slow ({duration:.2f}s). Expected under 1.0s.")
        sys.exit(1)
    else:
        with open("/home/user/workspace/success.log", "w") as f:
            f.write("PASS")
        print(f"PASS: Completed in {duration:.4f}s")

if __name__ == "__main__":
    test_performance()
'''


def test_00_test_perf_restored_exactly_and_executed():
    assert os.path.isfile(PERF_PATH), f"Expected {PERF_PATH} to be restored from the trash."
    with open(PERF_PATH, "rb") as f:
        restored = f.read()
    assert restored == EXPECTED_PERF, "test_perf.py was not restored exactly."

    try:
        os.unlink(LOG_PATH)
    except FileNotFoundError:
        pass

    completed = subprocess.run(
        [sys.executable, PERF_PATH],
        cwd=WORKSPACE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=8,
    )
    assert completed.returncode == 0, (
        "The restored performance test failed. Output:\n" + completed.stdout
    )


def test_success_log():
    assert os.path.isfile(LOG_PATH), (
        f"Expected {LOG_PATH} to exist. The restored test script might not have run or may have failed."
    )
    with open(LOG_PATH, "rb") as f:
        content = f.read()
    assert content == b"PASS", f"Expected success.log to contain exactly 'PASS', got {content!r}"


def test_data_processor_assertion():
    assert os.path.isfile(DP_PATH), f"Expected {DP_PATH} to exist."
    with open(DP_PATH, "r") as f:
        content = f.read()

    assert "assert isinstance(data, list)" in content, (
        "The required assertion 'assert isinstance(data, list)' is missing from data_processor.py"
    )

    tree = ast.parse(content, filename=DP_PATH)
    functions = [
        node for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == "get_unique_elements"
    ]
    assert len(functions) == 1, "Expected exactly one top-level get_unique_elements function."
    function = functions[0]
    assert function.body, "get_unique_elements has no body."
    first = function.body[0]
    assert isinstance(first, ast.Assert), (
        "assert isinstance(data, list) must be the first statement in get_unique_elements."
    )
    expected = ast.parse("assert isinstance(data, list)").body[0]
    assert ast.dump(first, include_attributes=False) == ast.dump(expected, include_attributes=False), (
        "The first statement must be exactly: assert isinstance(data, list)"
    )


def test_data_processor_functionality():
    sys.path.insert(0, WORKSPACE)
    try:
        from data_processor import get_unique_elements
    except ImportError as e:
        assert False, f"Could not import data_processor.py: {e}"
    except SyntaxError as e:
        assert False, f"Syntax error in data_processor.py: {e}"

    test_data = [1, 2, 2, 3, 1, 4, 4, 5]
    try:
        result = get_unique_elements(test_data)
    except AssertionError:
        assert False, "get_unique_elements raised an AssertionError with valid list input."
    except Exception as e:
        assert False, f"get_unique_elements raised an unexpected exception: {e}"

    assert isinstance(result, list), f"get_unique_elements must return a list, got {type(result).__name__}"
    assert sorted(result) == [1, 2, 3, 4, 5], (
        f"get_unique_elements did not return the correct unique elements. Got: {result}"
    )


def test_large_derived_input_is_correct_and_fast():
    probe = r'''
import secrets
import sys
import time
sys.path.insert(0, "/home/user/workspace")
from data_processor import get_unique_elements

rng = secrets.SystemRandom()
values = set()
while len(values) < 100000:
    values.add(secrets.randbits(128))
unique_values = list(values)
data = unique_values + unique_values[::3]
rng.shuffle(data)
start = time.monotonic()
result = get_unique_elements(data)
elapsed = time.monotonic() - start
if not isinstance(result, list):
    raise AssertionError(f"Expected a list, got {type(result).__name__}")
if len(result) != len(values) or len(set(result)) != len(result) or set(result) != values:
    raise AssertionError("Incorrect result for derived large input")
if elapsed > 2.0:
    raise AssertionError(f"Large derived input took {elapsed:.3f}s; expected an O(n) implementation")
'''
    completed = subprocess.run(
        [sys.executable, "-c", probe],
        cwd=WORKSPACE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=6,
    )
    assert completed.returncode == 0, (
        "get_unique_elements failed the large derived correctness/performance check. Output:\n"
        + completed.stdout
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
