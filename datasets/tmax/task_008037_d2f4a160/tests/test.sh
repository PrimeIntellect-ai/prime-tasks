#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

import pytest

BASE_DIR = "/home/user/release_prep"
SRC_DIR = os.path.join(BASE_DIR, "src")


def run_python(source, timeout=15):
    env = os.environ.copy()
    env["PYTHONPATH"] = os.pathsep.join([SRC_DIR, BASE_DIR])
    result = subprocess.run(
        [sys.executable, "-c", source],
        cwd=BASE_DIR,
        env=env,
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    return json.loads(result.stdout.strip().splitlines()[-1])


def test_c_extension_compiled():
    """Verify the existing artifact and that setup.py can really rebuild it."""
    so_files = glob.glob(os.path.join(BASE_DIR, "token_validator.*.so"))
    assert len(so_files) > 0, "The C extension token_validator.*.so was not found in the base directory. Did you fix setup.py and run build_ext?"

    for path in so_files:
        os.remove(path)
    shutil.rmtree(os.path.join(BASE_DIR, "build"), ignore_errors=True)

    result = subprocess.run(
        [sys.executable, "setup.py", "build_ext", "--inplace"],
        cwd=BASE_DIR,
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert result.returncode == 0, result.stdout + result.stderr

    rebuilt = glob.glob(os.path.join(BASE_DIR, "token_validator.*.so"))
    assert rebuilt, "setup.py did not produce token_validator.*.so"

    data = run_python("import token_validator, json; print(json.dumps({'value': token_validator.validate('test')}))")
    assert data["value"] == 1


def test_setup_py_fixed():
    """Retain the original assertion that setup.py declares libm linkage."""
    setup_file = os.path.join(BASE_DIR, "setup.py")
    assert os.path.isfile(setup_file), "setup.py is missing."
    with open(setup_file, "r") as f:
        content = f.read()
    assert "libraries" in content and "'m'" in content.replace('"', "'"), "setup.py does not seem to link the math library (libraries=['m'])."


def test_app_rate_limiting_and_history():
    """Retain the original burst/history checks."""
    sys.path.insert(0, SRC_DIR)
    try:
        import app
    except ImportError:
        pytest.fail("Could not import app.py")

    assert hasattr(app, "RateLimitExceeded"), "RateLimitExceeded exception is not defined in app.py"
    RateLimitExceeded = app.RateLimitExceeded

    app.HISTORY = ["old"] * 100
    try:
        app.process_request("new_token")
    except RateLimitExceeded:
        pass
    assert len(app.HISTORY) <= 20, f"Memory leak not fixed: HISTORY list size is {len(app.HISTORY)}, expected <= 20"

    app.HISTORY = []
    success_count = 0
    exception_count = 0
    time.sleep(1.1)
    for _ in range(10):
        try:
            app.process_request("test_token")
            success_count += 1
        except RateLimitExceeded:
            exception_count += 1

    assert success_count == 5, f"Rate limiter allowed {success_count} requests, expected exactly 5."
    assert exception_count == 5, f"Rate limiter raised exception {exception_count} times, expected exactly 5."


def test_rate_limit_is_rolling_not_fixed_window():
    """Exercise staggered requests so resetting a fixed counter cannot pass."""
    staggered = run_python(r'''
import json, time, app
E = app.RateLimitExceeded

def calls(n):
    ok = 0
    for _ in range(n):
        try:
            app.process_request("rolling")
            ok += 1
        except E:
            pass
    return ok

first = calls(3)
time.sleep(0.62)
second = calls(2)
time.sleep(0.46)
third = calls(5)
print(json.dumps([first, second, third]))
''')
    assert staggered == [3, 2, 3], f"Limiter is not enforcing a rolling one-second window: {staggered}"

    boundary = run_python(r'''
import json, time, app
E = app.RateLimitExceeded

def calls(n):
    ok = 0
    for _ in range(n):
        try:
            app.process_request("boundary")
            ok += 1
        except E:
            pass
    return ok

fraction = time.time() % 1.0
time.sleep((0.72 - fraction) % 1.0)
first = calls(5)
time.sleep(0.32)
second = calls(5)
print(json.dumps([first, second]))
''')
    assert boundary == [5, 0], f"Limiter reset at a fixed clock boundary instead of using a rolling window: {boundary}"


def test_history_always_keeps_exactly_the_latest_twenty():
    data = run_python(r'''
import json, time, app
errors = 0
for i in range(21):
    try:
        app.process_request("token-%02d" % i)
    except app.RateLimitExceeded:
        errors += 1
    time.sleep(0.22)
print(json.dumps({"errors": errors, "history": app.HISTORY}))
''', timeout=15)
    assert data["errors"] == 0, "Paced requests unexpectedly hit the rate limit"
    expected = ["token-%02d" % i for i in range(1, 21)]
    assert data["history"] == expected, f"HISTORY does not contain exactly the most recent 20 tokens: {data['history']}"


def test_verification_script_results():
    """Actually execute verify.py and observe its imports and ten calls."""
    verify_file = os.path.join(BASE_DIR, "verify.py")
    results_file = os.path.join(BASE_DIR, "test_results.txt")
    assert os.path.isfile(verify_file), "verify.py was not created."

    if os.path.exists(results_file):
        os.remove(results_file)

    with tempfile.TemporaryDirectory() as instrumentation:
        evidence_file = os.path.join(instrumentation, "evidence.json")
        sitecustomize = r'''
import atexit
import json
import os
import sys
import app

_calls = []
_original = app.process_request

def _observed(token):
    _calls.append(token)
    return _original(token)

app.process_request = _observed

@atexit.register
def _write_evidence():
    with open(os.environ["VERIFY_EVIDENCE"], "w") as f:
        json.dump({
            "calls": _calls,
            "token_validator_imported": "token_validator" in sys.modules,
            "history_size": len(app.HISTORY),
        }, f)
'''
        with open(os.path.join(instrumentation, "sitecustomize.py"), "w") as f:
            f.write(sitecustomize)

        env = os.environ.copy()
        env["VERIFY_EVIDENCE"] = evidence_file
        env["PYTHONPATH"] = os.pathsep.join([instrumentation, SRC_DIR, BASE_DIR])
        result = subprocess.run(
            [sys.executable, verify_file],
            cwd=BASE_DIR,
            env=env,
            text=True,
            capture_output=True,
            timeout=20,
        )
        assert result.returncode == 0, result.stdout + result.stderr
        assert os.path.isfile(evidence_file), "Could not observe verify.py execution"
        with open(evidence_file) as f:
            evidence = json.load(f)

    assert evidence["token_validator_imported"], "verify.py did not import token_validator"
    assert evidence["calls"] == ["test_token"] * 10, "verify.py did not make exactly 10 calls to process_request('test_token')"

    assert os.path.isfile(results_file), "test_results.txt was not created by verify.py."
    with open(results_file, "r") as f:
        content = f.read().strip()

    match = re.fullmatch(r"Successful: (\d+), History Size: (\d+)", content)
    assert match, f"test_results.txt has the wrong format. Content: {content}"
    assert int(match.group(1)) == 5, f"test_results.txt does not contain 'Successful: 5'. Content: {content}"
    assert int(match.group(2)) == evidence["history_size"], "verify.py did not report the actual final HISTORY size"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
