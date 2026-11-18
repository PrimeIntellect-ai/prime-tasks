#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import inspect
import os
import pwd
import subprocess


def fibonacci_mod(n, modulus=100000):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, (a + b) % modulus
    return a


def test_recovered_key_exists_and_correct():
    """Check if the recovered API key is correct."""
    path = "/home/user/recovered_key.txt"
    assert os.path.isfile(path), f"File {path} does not exist. Did you recover the API key?"

    with open(path, "r") as f:
        content = f.read().strip()

    expected_key = "SK-9942-ABCF-1111"
    assert content == expected_key, f"Recovered key is incorrect. Expected '{expected_key}', got '{content}'."


def test_compute_function_is_repaired():
    """Import the submitted artifact and exercise its mathematical logic."""
    script = "/home/user/math_tool/compute.py"
    assert os.path.isfile(script), f"File {script} does not exist."

    helper = r'''
import importlib.util
import inspect

path = "/home/user/math_tool/compute.py"
spec = importlib.util.spec_from_file_location("submitted_compute", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert hasattr(module, "compute_math") and callable(module.compute_math), "compute_math is missing or not callable"
fn = module.compute_math
sig = inspect.signature(fn)

try:
    sig.bind(0)
    accepts_n = True
except TypeError:
    accepts_n = False

if accepts_n:
    cases = [0, 1, 2, 10, 100, 4999, 5000]
    for n in cases:
        a, b = 0, 1
        for _ in range(n):
            a, b = b, (a + b) % 100000
        actual = fn(n)
        assert actual == a, f"compute_math({n}) returned {actual!r}, expected {a}"
else:
    sig.bind()
    a, b = 0, 1
    for _ in range(5000):
        a, b = b, (a + b) % 100000
    actual = fn()
    assert actual == a, f"compute_math() returned {actual!r}, expected {a}"
'''
    try:
        completed = subprocess.run(
            ["/usr/bin/python3", "-c", helper],
            cwd="/home/user/math_tool",
            capture_output=True,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        raise AssertionError("compute_math did not complete efficiently")

    assert completed.returncode == 0, (
        "The repaired compute_math implementation failed:\n"
        + completed.stdout
        + completed.stderr
    )


def test_result_exists_and_correct():
    """Run compute.py and verify that it generates the correct report itself."""
    script = "/home/user/math_tool/compute.py"
    result_path = "/home/user/result.txt"
    unauthorized_path = "/opt/restricted_math_out.txt"
    assert os.path.isfile(script), f"File {script} does not exist."

    for path in (result_path, unauthorized_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    account = pwd.getpwnam("user")

    def demote_to_user():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    try:
        completed = subprocess.run(
            ["/usr/bin/python3", script],
            cwd="/home/user/math_tool",
            env={"HOME": account.pw_dir, "PATH": "/usr/local/bin:/usr/bin:/bin"},
            capture_output=True,
            text=True,
            timeout=10,
            preexec_fn=demote_to_user,
        )
    except subprocess.TimeoutExpired:
        raise AssertionError("compute.py did not complete efficiently")

    assert completed.returncode == 0, (
        f"compute.py exited with status {completed.returncode}:\n"
        + completed.stdout
        + completed.stderr
    )
    assert not os.path.exists(unauthorized_path), (
        f"compute.py still wrote to the unauthorized path {unauthorized_path}"
    )
    assert os.path.isfile(result_path), f"File {result_path} does not exist. Did you fix the script and run it?"

    expected_result = str(fibonacci_mod(5000))
    with open(result_path, "r") as f:
        content = f.read().strip()

    assert content == expected_result, f"Math result is incorrect. Expected '{expected_result}', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
