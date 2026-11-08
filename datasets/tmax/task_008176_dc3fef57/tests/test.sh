#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import os
import secrets
import string
import subprocess

REPO = "/home/user/suspicious_repo"
FLAG_PATH = "/home/user/flag.txt"
AST_REPR = '["F", "L", "A", "G", "{", ["r", "3", "v", "3", "r", "s", "3"], "_", "3", "n", "g", "1", "n", "3", "3", "r", "}"]'
EXPECTED_ANALYZE = '''import sys
import os

# Attacker forces local lib directory to shadow standard library
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lib'))
import hashlib # Will fail until lib/hashlib.py is removed
import vm

if len(sys.argv) < 2:
    print("Usage: python3 analyze.py <key>")
    sys.exit(1)

key = sys.argv[1]

with open(os.path.join(os.path.dirname(__file__), 'payload.dat'), 'r') as f:
    data = f.read()

# XOR Decryption
decrypted = "".join(chr(ord(c) ^ ord(key[i % len(key)])) for i, c in enumerate(data))

try:
    ast_tree = eval(decrypted)
    result = vm.evaluate(ast_tree)
    with open('/home/user/flag.txt', 'w') as f:
        f.write(result)
    print("Successfully wrote to /home/user/flag.txt")
except Exception as e:
    print(f"Failed to evaluate: {e}")
    sys.exit(1)
'''


def independent_evaluate(node):
    if isinstance(node, str):
        return node
    if isinstance(node, list):
        return "".join(independent_evaluate(item) for item in node)
    return ""


def recover_key_from_history(payload):
    history = subprocess.run(
        ["/usr/bin/git", "-C", REPO, "log", "--all", "--format=%H", "--", "secret_key.txt"],
        text=True, capture_output=True, timeout=10
    )
    assert history.returncode == 0, history.stderr

    for commit in history.stdout.splitlines():
        shown = subprocess.run(
            ["/usr/bin/git", "-C", REPO, "show", f"{commit}:secret_key.txt"],
            text=True, capture_output=True, timeout=10
        )
        if shown.returncode != 0:
            continue
        key = shown.stdout.strip()
        if not key:
            continue
        decrypted = "".join(chr(ord(c) ^ ord(key[i % len(key)])) for i, c in enumerate(payload))
        if decrypted == AST_REPR:
            return key
    raise AssertionError("No usable decryption key was recoverable from git history.")


def test_pipeline_is_repaired_and_executes():
    analyze_path = os.path.join(REPO, "analyze.py")
    payload_path = os.path.join(REPO, "payload.dat")
    assert os.path.isfile(analyze_path), f"File {analyze_path} is missing."
    assert os.path.isfile(payload_path), f"File {payload_path} is missing."

    with open(analyze_path, "r") as f:
        assert f.read() == EXPECTED_ANALYZE, "analyze.py was replaced or altered instead of repairing the supplied pipeline."

    with open(payload_path, "r") as f:
        payload = f.read()
    key = recover_key_from_history(payload)

    # Verify that the repaired shadowed dependency provides real hashlib behavior.
    hashlib_check = subprocess.run(
        ["/usr/bin/python3", "-c",
         "import sys; sys.path.insert(0, '/home/user/suspicious_repo/lib'); import hashlib; "
         "assert hashlib.sha256(b'abc').hexdigest() == "
         "'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'"],
        cwd=REPO, text=True, capture_output=True, timeout=10,
        env={"PATH": "/usr/bin:/bin", "PYTHONPATH": ""}
    )
    assert hashlib_check.returncode == 0, hashlib_check.stdout + hashlib_check.stderr

    # Remove any prewritten answer and actually execute the required artifact.
    if os.path.exists(FLAG_PATH):
        os.remove(FLAG_PATH)
    run = subprocess.run(
        ["/usr/bin/python3", analyze_path, key],
        cwd=REPO, text=True, capture_output=True, timeout=15,
        env={"PATH": "/usr/bin:/bin", "PYTHONPATH": ""}
    )
    assert run.returncode == 0, run.stdout + run.stderr
    assert os.path.isfile(FLAG_PATH), "analyze.py completed without creating /home/user/flag.txt."

    expected = independent_evaluate(ast.literal_eval(AST_REPR))
    with open(FLAG_PATH, "r") as f:
        actual = f.read()
    assert actual == expected, f"Executed pipeline produced {actual!r}, expected {expected!r}."


def test_vm_behavior_on_fresh_nested_inputs():
    vm_path = os.path.join(REPO, "vm.py")
    assert os.path.isfile(vm_path), f"File {vm_path} is missing."
    spec = importlib.util.spec_from_file_location("submitted_vm", vm_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    token = "".join(secrets.choice(string.ascii_letters) for _ in range(24))
    cases = [
        [token[:5], [token[5:11], [token[11:17]]], token[17:]],
        [[[[token]]]],
        [token, 123, None, [False, token[::-1]]],
        [],
    ]
    for case in cases:
        assert module.evaluate(case) == independent_evaluate(case)


def test_flag_file_exists():
    flag_path = "/home/user/flag.txt"
    assert os.path.isfile(flag_path), f"File {flag_path} does not exist. The pipeline was not successfully executed."


def test_flag_content():
    flag_path = "/home/user/flag.txt"
    assert os.path.isfile(flag_path), f"File {flag_path} is missing."

    # Recompute the expected flag from the AST structure in the truth data
    ast_repr = '["F", "L", "A", "G", "{", ["r", "3", "v", "3", "r", "s", "3"], "_", "3", "n", "g", "1", "n", "3", "3", "r", "}"]'
    ast_tree = ast.literal_eval(ast_repr)

    def evaluate(node):
        if isinstance(node, str):
            return node
        elif isinstance(node, list):
            return "".join([evaluate(item) for item in node])
        else:
            return ""

    expected_flag = evaluate(ast_tree)

    with open(flag_path, "r") as f:
        actual_flag = f.read().strip()

    assert actual_flag == expected_flag, f"The content of {flag_path} is incorrect. Expected '{expected_flag}', but got '{actual_flag}'."


def test_vm_script_fixed():
    vm_path = "/home/user/suspicious_repo/vm.py"
    assert os.path.isfile(vm_path), f"File {vm_path} is missing."

    with open(vm_path, "r") as f:
        content = f.read()

    # The original bug was `evaluate(node)` inside the list comprehension
    # A correct fix would use `evaluate(item)` or similar logic that doesn't pass the same `node` recursively
    assert "evaluate(item)" in content or "evaluate(node)" not in content, \
        "The infinite recursion bug in vm.py does not appear to be fixed."


def test_environment_misconfiguration_fixed():
    hashlib_path = "/home/user/suspicious_repo/lib/hashlib.py"
    # The misconfiguration can be fixed by removing the file or changing its content
    if os.path.isfile(hashlib_path):
        with open(hashlib_path, "r") as f:
            content = f.read()
        assert "raise ImportError" not in content, \
            "The environment misconfiguration in lib/hashlib.py is still present."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
