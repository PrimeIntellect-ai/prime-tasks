#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import stat
import subprocess
import uuid

import pytest


def test_config_secure_json():
    secure_config_path = '/home/user/project/config_secure.json'
    assert os.path.isfile(secure_config_path), f"File missing: {secure_config_path}"

    with open(secure_config_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{secure_config_path} is not valid JSON")

    assert "credentials" in data, "Missing 'credentials' object in secure config"
    creds = data["credentials"]

    assert creds.get("api_key") == "***MASKED***", "api_key was not properly masked"
    assert creds.get("password") == "***MASKED***", "password was not properly masked"
    assert creds.get("user") == "admin", "user key was modified or is missing"
    assert data.get("app") == "my_app", "app key was modified or is missing"


def test_patch_applied():
    server_js_path = '/home/user/project/src/server.js'
    assert os.path.isfile(server_js_path), f"File missing: {server_js_path}"

    with open(server_js_path, 'r') as f:
        content = f.read()

    assert "app.disable('x-powered-by');" in content, "The security patch was not successfully applied to server.js"

    expected = (
        "const express = require('express');\n"
        "const app = express();\n"
        "app.disable('x-powered-by');\n"
        "app.get('/', (req, res) => res.send('Hello'));\n"
        "app.listen(8080);\n"
    )
    assert content == expected, "server.js was not preserved exactly while applying security.patch"


def test_leaked_file_deleted():
    leaked_script_path = '/home/user/project/src/leaked_script.py'
    assert not os.path.exists(leaked_script_path), f"The leaked file {leaked_script_path} was not deleted"


def test_deleted_file_log():
    log_path = '/home/user/project/deleted_file.log'
    assert os.path.isfile(log_path), f"File missing: {log_path}"

    with open(log_path, 'r') as f:
        content = f.read().strip()

    assert content == "leaked_script.py", f"Expected 'leaked_script.py' in {log_path}, got '{content}'"


def run_ci(script_path):
    return subprocess.run(
        [script_path],
        cwd='/home/user/project',
        capture_output=True,
        timeout=10,
    )


def test_ci_check_script():
    script_path = '/home/user/project/ci_check.sh'
    assert os.path.isfile(script_path), f"Script missing: {script_path}"

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable"

    result = run_ci(script_path)
    assert result.returncode == 0, f"Script {script_path} returned {result.returncode} instead of 0 when no secrets are present"

    test_secret_file = '/home/user/project/src/temp_test_secret.txt'
    try:
        with open(test_secret_file, 'w') as f:
            f.write("Here is a SECRET_123 string")

        result_with_secret = run_ci(script_path)
        assert result_with_secret.returncode == 1, f"Script {script_path} did not return 1 when a secret was introduced"
    finally:
        if os.path.exists(test_secret_file):
            os.remove(test_secret_file)

    # Exercise recursive searching using unpredictable paths. The same files are
    # alternated between equal-length harmless and secret-bearing contents so a
    # check based only on file names, counts, or sizes cannot satisfy the tests.
    token = uuid.uuid4().hex
    probe_root = f'/home/user/project/src/.ci_probe_{token}'
    probe_files = [
        os.path.join(probe_root, f'flat_{uuid.uuid4().hex}.txt'),
        os.path.join(probe_root, f'nested_{uuid.uuid4().hex}', f'data_{uuid.uuid4().hex}.bin'),
        os.path.join(probe_root, '.hidden', f'hidden_{uuid.uuid4().hex}'),
        os.path.join(probe_root, 'directory with spaces', f'file with spaces {uuid.uuid4().hex}.txt'),
    ]
    harmless = b'prefix PUBLIC_987 suffix\n'
    secret = b'prefix SECRET_987 suffix\n'

    try:
        for path in probe_files:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, 'wb') as f:
                f.write(harmless)

        result_harmless = run_ci(script_path)
        assert result_harmless.returncode == 0, (
            f"Script {script_path} returned {result_harmless.returncode} for recursively nested files without SECRET_"
        )

        selected = probe_files[int(token[:8], 16) % len(probe_files)]
        with open(selected, 'wb') as f:
            f.write(secret)

        result_nested_secret = run_ci(script_path)
        assert result_nested_secret.returncode == 1, (
            f"Script {script_path} did not detect SECRET_ in randomized nested file {selected}"
        )

        with open(selected, 'wb') as f:
            f.write(harmless)
        result_restored = run_ci(script_path)
        assert result_restored.returncode == 0, (
            f"Script {script_path} returned {result_restored.returncode} after the randomized secret was removed"
        )

        for path in probe_files:
            with open(path, 'wb') as f:
                f.write(secret)
        result_multiple = run_ci(script_path)
        assert result_multiple.returncode == 1, (
            f"Script {script_path} did not detect SECRET_ across randomized files"
        )
    finally:
        shutil.rmtree(probe_root, ignore_errors=True)


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
