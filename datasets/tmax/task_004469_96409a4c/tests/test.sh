#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib
import os
import re
import runpy
import subprocess
import sys

import pytest


def test_leaked_token_extracted():
    token_path = "/home/user/leaked_token.txt"
    dump_path = "/home/user/dump.bin"
    assert os.path.isfile(token_path), f"The file {token_path} does not exist."

    with open(token_path, "r") as f:
        content = f.read().strip()

    # Preserve the original assertion.
    assert content == "SECRET_TOKEN_77X91_PLUTO", f"Expected token 'SECRET_TOKEN_77X91_PLUTO', but got '{content}'."

    # Independently derive the expected token from the supplied dump.
    with open(dump_path, "rb") as f:
        dump = f.read()
    matches = re.findall(
        rb'"user_id"\s*:\s*"admin_01"\s*,\s*"token"\s*:\s*"(SECRET_TOKEN_[^"]+)"',
        dump,
    )
    assert len(matches) == 1, "Could not uniquely identify admin_01's token in the memory dump."
    expected = matches[0].decode("utf-8")
    assert content == expected, "leaked_token.txt does not contain the token associated with admin_01 in dump.bin."


def test_cache_size_calculated():
    size_path = "/home/user/cache_size.txt"
    assert os.path.isfile(size_path), f"The file {size_path} does not exist."

    with open(size_path, "r") as f:
        content = f.read().strip()

    # Preserve the original assertion.
    assert content == "3", f"Expected cache size '3', but got '{content}'."


def test_mre_script_exists_and_valid():
    mre_path = "/home/user/mre.py"
    assert os.path.isfile(mre_path), f"The file {mre_path} does not exist."

    with open(mre_path, "r") as f:
        content = f.read()

    try:
        tree = ast.parse(content)
    except SyntaxError as e:
        pytest.fail(f"The file {mre_path} contains invalid Python syntax: {e}")

    # Preserve the original app.worker import check.
    imports_app_worker = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if "app.worker" in alias.name:
                    imports_app_worker = True
        elif isinstance(node, ast.ImportFrom):
            if node.module and "app.worker" in node.module:
                imports_app_worker = True
            elif node.module == "app" and any(alias.name == "worker" for alias in node.names):
                imports_app_worker = True

    assert imports_app_worker, f"The script {mre_path} does not seem to import from 'app.worker'."

    # The instruction specifically requires importing both artifacts from app.worker.
    imported_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module == "app.worker":
            imported_names.update(alias.name for alias in node.names)
    assert "process_user_payload" in imported_names, "mre.py must import process_user_payload from app.worker."
    assert "_request_cache" in imported_names, "mre.py must import the global cache variable from app.worker."

    sys.path.insert(0, "/home/user")
    try:
        worker = importlib.import_module("app.worker")
        real_function = worker.process_user_payload

        def exercise(seed_count):
            calls = []
            worker._request_cache.clear()
            for i in range(seed_count):
                worker._request_cache[f"preexisting-{i}"] = ["seed"]

            def recording_function(user_id, payload):
                calls.append((user_id, payload))
                return real_function(user_id, payload)

            worker.process_user_payload = recording_function
            try:
                if os.path.exists("/home/user/cache_size.txt"):
                    os.unlink("/home/user/cache_size.txt")
                runpy.run_path(mre_path, run_name="__main__")
            finally:
                worker.process_user_payload = real_function

            assert calls == [
                ("test1", "dummy_data"),
                ("test2", "dummy_data"),
                ("test3", "dummy_data"),
            ], "mre.py must make exactly the three required calls in order."
            assert os.path.isfile("/home/user/cache_size.txt"), "Running mre.py did not create cache_size.txt."
            with open("/home/user/cache_size.txt", "r") as f:
                result = f.read().strip()
            expected_size = str(seed_count + 3)
            assert result == expected_size, f"mre.py did not write the calculated cache length; expected {expected_size}, got {result!r}."

        # Vary initial cache state so a hard-coded value cannot pass.
        exercise(0)
        exercise(2)
    finally:
        if sys.path and sys.path[0] == "/home/user":
            sys.path.pop(0)

    # Execute the submitted artifact normally against the real module and leave
    # the required final output in place.
    if os.path.exists("/home/user/cache_size.txt"):
        os.unlink("/home/user/cache_size.txt")
    completed = subprocess.run(
        [sys.executable, mre_path],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert completed.returncode == 0, f"mre.py failed when executed: {completed.stderr}"
    assert os.path.isfile("/home/user/cache_size.txt"), "Normal execution of mre.py did not create cache_size.txt."
    with open("/home/user/cache_size.txt", "r") as f:
        assert f.read().strip() == "3", "Normal execution of mre.py must write a cache size of 3."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
