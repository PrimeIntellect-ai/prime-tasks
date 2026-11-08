#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'DIRECT_EOF' > /tmp/run_vendored_simplejson.py
import os
import sys

VENDOR_ROOT = "/app/simplejson-3.19.1"
sys.path.insert(0, VENDOR_ROOT)
import simplejson

origin = os.path.realpath(simplejson.__file__)
expected_root = os.path.realpath(os.path.join(VENDOR_ROOT, "simplejson")) + os.sep
if not origin.startswith(expected_root):
    raise RuntimeError(f"Imported simplejson from unexpected path: {origin}")

print(origin)
data = sys.stdin.read()
try:
    simplejson.loads(data)
    print("SUCCESS")
except simplejson.errors.JSONDecodeError:
    print("ERROR")
DIRECT_EOF

mkdir -p /tmp/importcheck
cat << 'IMPORT_EOF' > /tmp/importcheck/sitecustomize.py
import atexit
import os
import sys

EXPECTED = os.path.realpath("/app/simplejson-3.19.1/simplejson") + os.sep

def verify_vendored_import():
    module = sys.modules.get("simplejson")
    path = os.path.realpath(getattr(module, "__file__", "")) if module else ""
    if not path.startswith(EXPECTED):
        try:
            sys.stdout.flush()
            sys.stderr.write("parse_fuzz.py did not import the vendored simplejson package\n")
            sys.stderr.flush()
        finally:
            os._exit(86)

atexit.register(verify_vendored_import)
IMPORT_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import random
import resource
import string
import subprocess
import pytest

ORACLE_PATH = "/usr/local/bin/oracle_parse_fuzz.py"
AGENT_PATH = "/home/user/parse_fuzz.py"
DIRECT_PATH = "/tmp/run_vendored_simplejson.py"
NUM_TESTS = 1000
TIMEOUT_SECS = 2.0
VENDOR_PACKAGE = os.path.realpath("/app/simplejson-3.19.1/simplejson") + os.sep


def generate_random_json_value(depth=0):
    if depth > 3:
        return random.choice([None, True, False, random.randint(-1000, 1000), "".join(random.choices(string.ascii_letters, k=5))])

    val_type = random.choice(['dict', 'list', 'int', 'string', 'bool', 'null'])
    if val_type == 'dict':
        return {f"key_{i}": generate_random_json_value(depth + 1) for i in range(random.randint(0, 3))}
    elif val_type == 'list':
        return [generate_random_json_value(depth + 1) for _ in range(random.randint(0, 3))]
    elif val_type == 'int':
        return random.randint(-10000, 10000)
    elif val_type == 'string':
        return "".join(random.choices(string.ascii_letters + string.digits + " \t\n", k=random.randint(0, 20)))
    elif val_type == 'bool':
        return random.choice([True, False])
    else:
        return None


def generate_fuzz_inputs(n):
    random.seed(42)
    inputs = []
    for _ in range(n):
        choice = random.random()
        if choice < 0.3:
            val = generate_random_json_value()
            inputs.append(json.dumps(val))
        elif choice < 0.6:
            val = generate_random_json_value()
            s = json.dumps(val)
            if len(s) > 2:
                if random.random() < 0.5:
                    s = s[:random.randint(1, len(s)-1)]
                else:
                    idx = random.randint(0, len(s)-1)
                    s = s[:idx] + random.choice(string.printable) + s[idx+1:]
            inputs.append(s)
        else:
            val = generate_random_json_value()
            if not isinstance(val, dict):
                val = {"a": val}
            s = json.dumps(val)
            s = s[:-1] + ', "unclosed": '
            if random.random() < 0.5:
                s += '{"nested": 1, '
            inputs.append(s)
    return inputs


def memory_limit():
    limit = 256 * 1024 * 1024
    resource.setrlimit(resource.RLIMIT_AS, (limit, limit))


def test_parse_fuzz_exists():
    assert os.path.isfile(AGENT_PATH), f"Target script {AGENT_PATH} is missing."


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle script {ORACLE_PATH} is missing."

    inputs = generate_fuzz_inputs(NUM_TESTS)
    for i, inp in enumerate(inputs):
        inp_bytes = inp.encode('utf-8')

        oracle_proc = subprocess.run(
            ["python3", ORACLE_PATH],
            input=inp_bytes,
            capture_output=True,
            timeout=TIMEOUT_SECS
        )
        oracle_out = oracle_proc.stdout.decode('utf-8', errors='replace').strip()
        oracle_err = oracle_proc.stderr.decode('utf-8', errors='replace').strip()
        oracle_code = oracle_proc.returncode

        try:
            agent_proc = subprocess.run(
                ["python3", AGENT_PATH],
                input=inp_bytes,
                capture_output=True,
                timeout=TIMEOUT_SECS
            )
            agent_out = agent_proc.stdout.decode('utf-8', errors='replace').strip()
            agent_err = agent_proc.stderr.decode('utf-8', errors='replace').strip()
            agent_code = agent_proc.returncode
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out (possible infinite loop/memory leak) on input:\n{inp!r}")

        assert agent_out == oracle_out, (
            f"Output mismatch on input {i}:\n"
            f"Input: {inp!r}\n"
            f"Oracle output: {oracle_out!r}\n"
            f"Agent output: {agent_out!r}\n"
            f"Oracle exit code: {oracle_code}, Agent exit code: {agent_code}"
        )
        assert agent_code == oracle_code, (
            f"Exit-code mismatch on input {i}: {inp!r}; "
            f"oracle={oracle_code}, agent={agent_code}; "
            f"oracle stderr={oracle_err!r}, agent stderr={agent_err!r}"
        )


def test_vendored_simplejson_directly():
    cases = [
        "{}",
        '{"a": 1}',
        '[1, 2, {"x": true}]',
        '{"a": 1, ',
        '{"test": "value", "b": ',
        '{"incomplete": ',
        '{"a": 1,}',
        '{"nested": {"x": 1, ',
        '{',
        '[1,',
        '"unterminated',
    ]

    for inp in cases:
        try:
            json.loads(inp)
            expected = "SUCCESS"
        except json.JSONDecodeError:
            expected = "ERROR"

        try:
            proc = subprocess.run(
                ["python3", DIRECT_PATH],
                input=inp.encode("utf-8"),
                capture_output=True,
                timeout=TIMEOUT_SECS,
                preexec_fn=memory_limit,
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Vendored simplejson timed out on input {inp!r}")

        stdout_lines = proc.stdout.decode("utf-8", errors="replace").splitlines()
        stderr = proc.stderr.decode("utf-8", errors="replace")
        assert proc.returncode == 0, (
            f"Vendored simplejson crashed on {inp!r}: code={proc.returncode}, stderr={stderr!r}"
        )
        assert len(stdout_lines) == 2, f"Unexpected direct-run output on {inp!r}: {stdout_lines!r}"
        assert os.path.realpath(stdout_lines[0]).startswith(VENDOR_PACKAGE), (
            f"Direct test imported the wrong simplejson: {stdout_lines[0]!r}"
        )
        assert stdout_lines[1] == expected, (
            f"Vendored simplejson mismatch on {inp!r}: expected {expected}, got {stdout_lines[1]!r}"
        )


def test_wrapper_imports_vendored_simplejson():
    env = os.environ.copy()
    old_pythonpath = env.get("PYTHONPATH")
    env["PYTHONPATH"] = "/tmp/importcheck" + (os.pathsep + old_pythonpath if old_pythonpath else "")
    proc = subprocess.run(
        ["python3", AGENT_PATH],
        input=b"{}",
        capture_output=True,
        timeout=TIMEOUT_SECS,
        env=env,
    )
    assert proc.returncode == 0, proc.stderr.decode("utf-8", errors="replace")
    assert proc.stdout.decode("utf-8", errors="replace").strip() == "SUCCESS"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
