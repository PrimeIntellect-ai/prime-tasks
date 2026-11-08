#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import subprocess
import sys

from packaging.requirements import Requirement
from packaging.utils import canonicalize_name

REPO_DIR = "/home/user/suspicious_tool"
TEST_FILE = "/home/user/test_c2_auth.py"
SECRET_TOKEN = "C2_TOK_77f9a2b4_exfiltrate"
REQUIRED_PACKAGES = {"pyjwt", "cryptography"}


def test_requirements_fixed_and_installable():
    req_path = os.path.join(REPO_DIR, "requirements.txt")
    assert os.path.isfile(req_path), f"File {req_path} does not exist."

    with open(req_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip() and not line.lstrip().startswith("#")]

    parsed_names = set()
    for line in lines:
        try:
            parsed_names.add(canonicalize_name(Requirement(line).name))
        except Exception as exc:
            raise AssertionError(f"Invalid requirement entry {line!r}: {exc}") from exc

    missing = REQUIRED_PACKAGES - parsed_names
    assert not missing, (
        "requirements.txt removed packages instead of resolving their versions. "
        f"Missing: {sorted(missing)}"
    )

    # Verify that pip can successfully resolve and install the requirements
    result = subprocess.run(
        [sys.executable, "-m", "pip", "install", "-r", req_path],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, (
        f"Failed to install requirements.txt. The dependency conflict may still exist.\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )


def test_test_file_exists_and_contains_secret():
    assert os.path.isfile(TEST_FILE), f"Test file {TEST_FILE} was not created."

    with open(TEST_FILE, "r", encoding="utf-8") as f:
        content = f.read()

    assert SECRET_TOKEN in content, (
        f"The test file {TEST_FILE} does not contain the correct recovered secret token."
    )


def test_test_file_imports_and_asserts_check_c2_auth():
    assert os.path.isfile(TEST_FILE), f"Test file {TEST_FILE} is missing."
    with open(TEST_FILE, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=TEST_FILE)

    imported_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module == "malware":
            for alias in node.names:
                if alias.name == "check_c2_auth":
                    imported_names.add(alias.asname or alias.name)

    assert imported_names, (
        "The test file must import check_c2_auth from malware."
    )

    asserted_call = False
    for function in ast.walk(tree):
        if isinstance(function, (ast.FunctionDef, ast.AsyncFunctionDef)) and function.name.startswith("test"):
            for node in ast.walk(function):
                if isinstance(node, ast.Assert):
                    for child in ast.walk(node.test):
                        if (
                            isinstance(child, ast.Call)
                            and isinstance(child.func, ast.Name)
                            and child.func.id in imported_names
                        ):
                            asserted_call = True

    assert asserted_call, (
        "A pytest test function must assert the result of the imported check_c2_auth function."
    )


def test_test_file_runs_successfully_and_calls_real_function():
    assert os.path.isfile(TEST_FILE), f"Test file {TEST_FILE} is missing."

    runner = r'''import inspect
import os
import sys
import pytest

repo_dir, test_file, secret = sys.argv[1:4]
sys.path.insert(0, repo_dir)
import malware

original = malware.check_c2_auth
observed = []

def monitored_check_c2_auth(token):
    result = original(token)
    real_test_file = os.path.realpath(test_file)
    if any(
        os.path.realpath(frame.frame.f_code.co_filename) == real_test_file
        and frame.function.startswith("test")
        for frame in inspect.stack()
    ):
        observed.append((token, result))
    return result

malware.check_c2_auth = monitored_check_c2_auth
status = pytest.main([test_file, "-q"])
if status != 0:
    raise SystemExit(status)
if not any(token == secret and result is True for token, result in observed):
    print("No executing pytest test called malware.check_c2_auth with the recovered token and received True.", file=sys.stderr)
    raise SystemExit(1)
'''

    env = os.environ.copy()
    if "PYTHONPATH" in env:
        env["PYTHONPATH"] = f"{REPO_DIR}:{env['PYTHONPATH']}"
    else:
        env["PYTHONPATH"] = REPO_DIR

    result = subprocess.run(
        [sys.executable, "-c", runner, REPO_DIR, TEST_FILE, SECRET_TOKEN],
        env=env,
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, (
        f"pytest execution of {TEST_FILE} failed. Ensure the test imports and calls "
        f"malware.check_c2_auth with the recovered token and asserts its result.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
