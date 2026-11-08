#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.machinery
import json
import os
import random
import re
import subprocess
import sys
import urllib.parse

import pytest

PROJECT = "/home/user/math_pr"


@pytest.fixture(scope="session", autouse=True)
def rebuild_extension():
    """Rebuild the submitted C extension so tests execute the current source."""
    for path in glob.glob(os.path.join(PROJECT, "mathstack*.so")):
        os.remove(path)

    proc = subprocess.run(
        [sys.executable, "setup.py", "build_ext", "--inplace", "--force"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert proc.returncode == 0, f"Building the C extension failed:\n{proc.stdout}"
    assert glob.glob(os.path.join(PROJECT, "mathstack*.so")), \
        "The build did not produce a mathstack extension in the project directory."


def test_verification_log():
    """Check if the verification log exists and contains the correct result."""
    log_path = "/home/user/verification.log"
    assert os.path.isfile(log_path), f"The file {log_path} is missing."

    with open(log_path, "r") as f:
        content = f.read().strip()

    # Expected result: -17 // 5 = -4. -4 * 2 = -8. 10*6 = 60. 60 + (-8) = 52.
    assert content == "52", f"Expected verification.log to contain '52', but found '{content}'"


def test_server_py_fixed():
    """Check if server.py decodes the URL."""
    server_path = "/home/user/math_pr/server.py"
    assert os.path.isfile(server_path), f"The file {server_path} is missing."

    with open(server_path, "r") as f:
        content = f.read()

    assert "unquote" in content, "server.py does not seem to decode the URL using unquote."


def test_mathstack_c_stack_size():
    """Check if the stack size in mathstack.c was increased to at least 100."""
    c_path = "/home/user/math_pr/mathstack.c"
    assert os.path.isfile(c_path), f"The file {c_path} is missing."

    with open(c_path, "r") as f:
        content = f.read()

    match = re.search(r'int\s+stack\s*\[\s*(\d+)\s*\]\s*;', content)
    assert match is not None, "Could not find stack array declaration in mathstack.c"

    size = int(match.group(1))
    assert size >= 100, f"Stack size in mathstack.c is {size}, but needs to be at least 100."


def test_mathstack_c_floor_division():
    """Check if mathstack.c implements floor division."""
    c_path = "/home/user/math_pr/mathstack.c"

    with open(c_path, "r") as f:
        content = f.read()

    div_block_match = re.search(r'strcmp\(token,\s*"DIV"\)\s*==\s*0\)(.*?)(?:else\s+if|else\s*\{)', content, re.DOTALL)
    if div_block_match:
        div_block = div_block_match.group(1)
        assert ("%" in div_block or "< 0" in div_block or "floor" in div_block or "^" in div_block or "div" in div_block or "a / b" not in div_block or "if" in div_block.replace("if (b == 0)", "").replace("if (top < 2)", "")), "mathstack.c does not seem to implement floor division correctly."


def test_extension_built():
    """Check if the C extension was built."""
    files = os.listdir(PROJECT)
    so_files = [f for f in files if f.startswith("mathstack.") and f.endswith(".so")]
    assert len(so_files) > 0, "The mathstack C extension (.so file) was not found in /home/user/math_pr."


def test_compiled_extension_behavior():
    """Execute the rebuilt extension on derived division and depth-100 cases."""
    rng = random.SystemRandom()
    cases = []

    # Exercise Python floor division with both sign combinations and nonzero remainders.
    for i in range(24):
        b = rng.randint(2, 97)
        a = rng.randint(101, 20000)
        if a % b == 0:
            a += 1
        if i % 2 == 0:
            a = -a
        else:
            b = -b
        cases.append((f"{a} {b} DIV", a // b))

    # This valid expression reaches a stack depth of exactly 100.
    values = [rng.randint(-50, 50) for _ in range(100)]
    depth_expr = " ".join(map(str, values)) + " " + " ".join(["ADD"] * 99)
    cases.append((depth_expr, sum(values)))

    runner = r'''
import importlib.machinery
import json
import os
import sys
import mathstack

cases = json.loads(sys.argv[1])
module_path = os.path.realpath(mathstack.__file__)
project = os.path.realpath(sys.argv[2])
assert os.path.commonpath([module_path, project]) == project
assert any(module_path.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES)
results = [mathstack.eval(expr) for expr, expected in cases]
print(json.dumps({"module": module_path, "results": results}))
'''
    proc = subprocess.run(
        [sys.executable, "-c", runner, json.dumps(cases), PROJECT],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert proc.returncode == 0, f"The rebuilt extension failed while being exercised:\n{proc.stderr}"
    lines = [line for line in proc.stdout.splitlines() if line.strip()]
    assert lines, "The extension behavior runner produced no result."
    payload = json.loads(lines[-1])
    assert payload["results"] == [expected for _, expected in cases]


def test_http_server_decodes_and_evaluates():
    """Run the submitted HTTP handler and verify encoded requests end to end."""
    rng = random.SystemRandom()
    cases = [
        ("-17 5 DIV 2 MUL 10 10 10 10 10 10 ADD ADD ADD ADD ADD ADD", 52)
    ]
    for _ in range(12):
        divisor = rng.randint(2, 31)
        numerator = -rng.randint(40, 5000)
        if numerator % divisor == 0:
            numerator -= 1
        multiplier = rng.randint(2, 9)
        expression = f"{numerator} {divisor} DIV {multiplier} MUL"
        cases.append((expression, (numerator // divisor) * multiplier))

    runner = r'''
import json
import socketserver
import sys
import threading
import urllib.parse
import urllib.request

import server

cases = json.loads(sys.argv[1])
httpd = socketserver.TCPServer(("127.0.0.1", 0), server.MathServer)
thread = threading.Thread(target=httpd.serve_forever, daemon=True)
thread.start()
try:
    port = httpd.server_address[1]
    results = []
    for expression, expected in cases:
        encoded = urllib.parse.quote(expression, safe="").replace("-", "%2D")
        url = f"http://127.0.0.1:{port}/eval/{encoded}"
        with urllib.request.urlopen(url, timeout=5) as response:
            results.append([response.status, response.read().decode().strip()])
    print(json.dumps(results))
finally:
    httpd.shutdown()
    httpd.server_close()
'''
    proc = subprocess.run(
        [sys.executable, "-c", runner, json.dumps(cases)],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert proc.returncode == 0, f"The HTTP server failed during requests:\n{proc.stderr}"
    lines = [line for line in proc.stdout.splitlines() if line.strip()]
    assert lines, "The HTTP server test produced no responses."
    responses = json.loads(lines[-1])
    assert len(responses) == len(cases)
    for response, (_, expected) in zip(responses, cases):
        assert response[0] == 200
        assert response[1] == str(expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
