#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import contextlib
import io
import json
import os
import secrets
import subprocess
import sys

APP_DIR = "/home/user/app"
PROCESSOR_PY = os.path.join(APP_DIR, "processor.py")
SOLUTION_TXT = "/home/user/solution.txt"


def test_processor_py_fixed():
    assert os.path.isfile(PROCESSOR_PY), f"File {PROCESSOR_PY} does not exist."
    with open(PROCESSOR_PY, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "def process_x" in content, "process_x function missing in processor.py"
    assert "def process_y" in content, "process_y function missing in processor.py"

    x_idx = content.find("def process_x")
    y_idx = content.find("def process_y")
    if y_idx < x_idx:
        y_content = content[y_idx:x_idx]
    else:
        y_content = content[y_idx:]

    lock_a_idx = y_content.find("with lock_a:")
    lock_b_idx = y_content.find("with lock_b:")
    assert lock_a_idx != -1, "lock_a not found in process_y"
    assert lock_b_idx != -1, "lock_b not found in process_y"
    assert lock_a_idx < lock_b_idx, "process_y must acquire lock_a before lock_b to fix the deadlock."

    # Require syntactically valid Python with both actual function definitions.
    tree = ast.parse(content, filename=PROCESSOR_PY)
    functions = {
        node.name: node
        for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    }
    assert "process_x" in functions, "process_x must be a real Python function"
    assert "process_y" in functions, "process_y must be a real Python function"

    # Execute both functions with unpredictable transaction IDs and instrument the
    # actual global locks. This proves that executable code acquires A, then B,
    # keeps B nested inside A, releases in reverse order, and retains the prints.
    cases = []
    for name, label in (("process_x", "X"), ("process_y", "Y")):
        for _ in range(2):
            cases.append([name, label, "VERIFY_" + secrets.token_hex(12)])

    runner = r'''
import contextlib
import importlib.util
import io
import json
import sys

path = sys.argv[1]
cases = json.loads(sys.argv[2])
marker = sys.argv[3]

spec = importlib.util.spec_from_file_location("submitted_processor", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
results = []

for function_name, label, txn_id in cases:
    events = []
    stack = []

    class TraceLock:
        def __init__(self, name):
            self.name = name
        def __enter__(self):
            events.append("enter_" + self.name)
            stack.append(self.name)
            return self
        def __exit__(self, exc_type, exc, tb):
            if not stack or stack[-1] != self.name:
                raise AssertionError("locks were not released in nested order")
            stack.pop()
            events.append("exit_" + self.name)
            return False

    module.lock_a = TraceLock("a")
    module.lock_b = TraceLock("b")
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        getattr(module, function_name)(txn_id)

    results.append({
        "function": function_name,
        "events": events,
        "stack": stack,
        "output": output.getvalue(),
        "expected_output": "Processed " + label + " " + txn_id + "\\n",
    })

print(marker + json.dumps(results, sort_keys=True))
'''

    marker = "RESULT_" + secrets.token_hex(16) + ":"
    try:
        completed = subprocess.run(
            [sys.executable, "-c", runner, PROCESSOR_PY, json.dumps(cases), marker],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=8,
        )
    except subprocess.TimeoutExpired:
        raise AssertionError("processor.py did not complete when executed")

    assert completed.returncode == 0, (
        "processor.py failed during execution:\n" + completed.stderr
    )
    result_lines = [
        line for line in completed.stdout.splitlines() if line.startswith(marker)
    ]
    assert result_lines, "processor.py execution did not return verification results"
    results = json.loads(result_lines[-1][len(marker):])

    assert len(results) == len(cases)
    for result in results:
        assert result["events"] == ["enter_a", "enter_b", "exit_b", "exit_a"], (
            f'{result["function"]} must acquire lock_a first, then lock_b, with lock_b nested inside lock_a'
        )
        assert result["stack"] == [], f'{result["function"]} did not release both locks'
        assert result["output"] == result["expected_output"], (
            f'{result["function"]} changed its core print behavior'
        )


def test_solution_txt_correct():
    assert os.path.isfile(SOLUTION_TXT), f"File {SOLUTION_TXT} does not exist."

    with open(SOLUTION_TXT, "r") as f:
        content = f.read().strip()

    expected = "TXN_33B2E1, TXN_88A9F0"
    assert content == expected, f"Expected solution.txt to contain exactly '{expected}', but got '{content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
