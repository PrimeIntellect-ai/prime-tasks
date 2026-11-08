#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import json
import os
import secrets
import subprocess
import sys

import pytest

APP_DIR = "/home/user/app"
EXT_DIR = os.path.join(APP_DIR, "ext")
LOG_FILE = "/home/user/migration_result.log"


def run_python(code, cwd, *args):
    proc = subprocess.run(
        [sys.executable, "-c", code, *args],
        cwd=cwd,
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert proc.returncode == 0, f"Python process failed:\nstdout: {proc.stdout}\nstderr: {proc.stderr}"
    return proc.stdout.strip()


def assert_extension_works(directory):
    valid = "v2_" + secrets.token_hex(12)
    invalid = "zz_" + secrets.token_hex(12)
    code = r'''
import inspect
import json
import os
import validator
expected = os.path.realpath(os.path.join(os.getcwd(), "validator.so"))
actual = os.path.realpath(validator.__file__)
assert actual == expected, (actual, expected)
assert inspect.isbuiltin(validator.validate_token), type(validator.validate_token)
print(json.dumps({
    "valid": validator.validate_token(%r),
    "invalid": validator.validate_token(%r),
    "embedded": validator.validate_token("xxv2_not_a_prefix"),
    "other_version": validator.validate_token("v3_not_valid")
}))
''' % (valid, invalid)
    data = json.loads(run_python(code, directory))
    assert data == {
        "valid": True,
        "invalid": False,
        "embedded": False,
        "other_version": False,
    }


def test_validator_c_updated_for_python3():
    filepath = os.path.join(EXT_DIR, "validator.c")
    assert os.path.isfile(filepath), f"File missing: {filepath}"

    with open(filepath, "r") as f:
        content = f.read()

    assert "Py_InitModule" not in content, "validator.c still contains Python 2 'Py_InitModule'."
    assert "PyModuleDef" in content, "validator.c does not contain 'PyModuleDef' for Python 3."
    assert "PyModule_Create" in content, "validator.c does not contain 'PyModule_Create' for Python 3."


def test_makefile_updated_for_python3():
    filepath = os.path.join(EXT_DIR, "Makefile")
    assert os.path.isfile(filepath), f"File missing: {filepath}"

    with open(filepath, "r") as f:
        content = f.read()

    assert "python3.10" in content, "Makefile does not include Python 3.10 headers."
    assert "python2.7" not in content, "Makefile still includes Python 2.7 headers."


def test_validator_so_copied():
    filepath = os.path.join(APP_DIR, "validator.so")
    assert os.path.isfile(filepath), f"Compiled extension missing at: {filepath}"
    with open(filepath, "rb") as f:
        assert f.read(4) == b"\x7fELF", "validator.so is not an ELF shared object."
    assert_extension_works(APP_DIR)


def test_make_rebuilds_same_working_extension():
    app_so = os.path.join(APP_DIR, "validator.so")
    assert os.path.isfile(app_so), f"Compiled extension missing at: {app_so}"

    ext_so = os.path.join(EXT_DIR, "validator.so")
    if os.path.exists(ext_so):
        os.remove(ext_so)
    proc = subprocess.run(
        ["make"], cwd=EXT_DIR, text=True, capture_output=True, timeout=30
    )
    assert proc.returncode == 0, f"make failed:\nstdout: {proc.stdout}\nstderr: {proc.stderr}"
    assert os.path.isfile(ext_so), "make did not produce ext/validator.so."
    with open(ext_so, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Built validator.so is not an ELF shared object."
    assert_extension_works(EXT_DIR)

    with open(app_so, "rb") as f:
        app_hash = hashlib.sha256(f.read()).digest()
    with open(ext_so, "rb") as f:
        ext_hash = hashlib.sha256(f.read()).digest()
    assert app_hash == ext_hash, "/home/user/app/validator.so is not the extension produced by make."


def test_config_py_created_and_has_rate_limit():
    filepath = os.path.join(APP_DIR, "config.py")
    assert os.path.isfile(filepath), f"config.py missing: {filepath}"

    with open(filepath, "r") as f:
        content = f.read()

    assert "RATE_LIMIT" in content, "config.py does not contain RATE_LIMIT."
    namespace = {}
    exec(compile(content, filepath, "exec"), namespace)
    assert namespace.get("RATE_LIMIT") == 100, "config.py must define RATE_LIMIT as 100."


def imports_rate_limit_from_config(filepath):
    with open(filepath, "r") as f:
        tree = ast.parse(f.read(), filename=filepath)
    return any(
        isinstance(node, ast.ImportFrom)
        and node.module == "config"
        and any(alias.name == "RATE_LIMIT" for alias in node.names)
        for node in tree.body
    )


def test_server_py_updated():
    filepath = os.path.join(APP_DIR, "server.py")
    assert os.path.isfile(filepath), f"File missing: {filepath}"

    with open(filepath, "r") as f:
        content = f.read()

    assert "RATE_LIMIT = 100" not in content, "server.py still defines RATE_LIMIT."
    assert "config" in content, "server.py does not import from config."
    assert imports_rate_limit_from_config(filepath), "server.py must import RATE_LIMIT from config."


def test_auth_py_updated():
    filepath = os.path.join(APP_DIR, "auth.py")
    assert os.path.isfile(filepath), f"File missing: {filepath}"

    with open(filepath, "r") as f:
        content = f.read()

    assert "from server import RATE_LIMIT" not in content, "auth.py still imports RATE_LIMIT from server."
    assert "config" in content, "auth.py does not import from config."
    assert imports_rate_limit_from_config(filepath), "auth.py must import RATE_LIMIT from config."


def test_application_import_and_request_flow():
    valid = "v2_" + secrets.token_hex(12)
    invalid = "no_" + secrets.token_hex(12)
    code = r'''
import json
import config
import auth
import server
assert config.RATE_LIMIT == 100
results = [
    server.handle_request({"token": %r, "count": 0}),
    server.handle_request({"token": %r, "count": 100}),
    server.handle_request({"token": %r, "count": 101}),
    server.handle_request({"token": %r, "count": 5}),
]
print(json.dumps(results))
''' % (valid, valid, valid, invalid)
    results = json.loads(run_python(code, APP_DIR))
    assert results == [
        {"status": "ok"},
        {"status": "ok"},
        {"status": "error"},
        {"status": "error"},
    ]


def test_migration_result_log_success():
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)
    proc = subprocess.run(
        [sys.executable, os.path.join(APP_DIR, "test_runner.py")],
        cwd=APP_DIR,
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert proc.returncode == 0, f"test_runner.py failed:\nstdout: {proc.stdout}\nstderr: {proc.stderr}"
    assert os.path.isfile(LOG_FILE), f"Migration result log missing: {LOG_FILE}. Did you run test_runner.py?"

    with open(LOG_FILE, "r") as f:
        content = f.read().strip()

    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail("migration_result.log does not contain valid JSON.")

    assert data.get("status") == "ok", f"Expected status 'ok', got: {data.get('status')}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
