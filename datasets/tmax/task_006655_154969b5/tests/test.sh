#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import secrets
import signal
import stat
import subprocess
import time


def get_expected_token():
    vuln_script_path = "/home/user/vuln_loop.sh"
    assert os.path.exists(vuln_script_path), f"Expected setup file {vuln_script_path} is missing."
    with open(vuln_script_path, "r") as f:
        content = f.read()

    match = re.search(r'/home/user/auth_tool\s+(\S+)', content)
    assert match is not None, "Could not extract token from vuln_loop.sh."
    return match.group(1)


def test_token_hash_file():
    hash_file_path = "/home/user/token_hash.txt"
    assert os.path.exists(hash_file_path), f"File {hash_file_path} does not exist."

    token = get_expected_token()
    expected_hash = hashlib.sha256(token.encode('utf-8')).hexdigest()

    with open(hash_file_path, "r") as f:
        actual_content = f.read().strip()

    actual_hash = actual_content.split()[0]
    assert actual_hash == expected_hash, (
        f"Hash in {hash_file_path} is incorrect. Expected {expected_hash}, got {actual_hash}."
    )


def test_secure_invoke_script_exists_and_executable():
    script_path = "/home/user/secure_invoke.sh"
    assert os.path.exists(script_path), f"File {script_path} does not exist."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {script_path} is not executable."


def test_secure_invoke_script_logic():
    script_path = "/home/user/secure_invoke.sh"
    assert os.path.exists(script_path), f"File {script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read()

    assert "SECRET_TOKEN" in content, "The script does not seem to use the SECRET_TOKEN environment variable."
    assert "token.txt" in content, "The script does not seem to read from /home/user/token.txt."

    lines = content.splitlines()
    for line in lines:
        if "auth_tool" in line and not line.strip().startswith("#"):
            match = re.search(r'auth_tool\s+.*\$', line)
            assert not match, "The script appears to pass arguments to auth_tool on the command line, which is insecure."


def test_secure_invoke_behavior():
    script_path = "/home/user/secure_invoke.sh"
    auth_path = "/home/user/auth_tool"
    token_path = "/home/user/token.txt"
    record_path = f"/tmp/auth_record_{secrets.token_hex(16)}.json"
    test_token = f"tk_dynamic_{secrets.token_hex(24)}"

    auth_contents = open(auth_path, "rb").read()
    auth_mode = stat.S_IMODE(os.stat(auth_path).st_mode)

    token_existed = os.path.exists(token_path)
    token_contents = open(token_path, "rb").read() if token_existed else None
    token_mode = stat.S_IMODE(os.stat(token_path).st_mode) if token_existed else None

    recorder = f'''#!/usr/bin/python3
import json
import os
import sys
with open({record_path!r}, "w") as f:
    json.dump({{"argv": sys.argv[1:], "secret": os.environ.get("SECRET_TOKEN")}}, f)
'''

    proc = None
    try:
        with open(token_path, "w") as f:
            f.write(test_token + "\n")
        os.chmod(token_path, 0o600)

        with open(auth_path, "w") as f:
            f.write(recorder)
        os.chmod(auth_path, 0o755)

        clean_env = {
            "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "HOME": "/home/user",
        }
        proc = subprocess.Popen(
            [script_path],
            env=clean_env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        try:
            stdout, stderr = proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            stdout, stderr = proc.communicate()
            raise AssertionError("secure_invoke.sh did not complete within 5 seconds")

        assert proc.returncode == 0, (
            f"secure_invoke.sh exited with status {proc.returncode}. "
            f"stdout={stdout!r}, stderr={stderr!r}"
        )

        deadline = time.time() + 2
        while not os.path.exists(record_path) and time.time() < deadline:
            time.sleep(0.05)

        assert os.path.exists(record_path), (
            "secure_invoke.sh did not invoke /home/user/auth_tool"
        )
        with open(record_path, "r") as f:
            record = json.load(f)

        assert record["secret"] == test_token, (
            "auth_tool did not receive the token from token.txt through SECRET_TOKEN"
        )
        assert record["argv"] == [], (
            f"auth_tool received command-line arguments: {record['argv']!r}"
        )
    finally:
        with open(auth_path, "wb") as f:
            f.write(auth_contents)
        os.chmod(auth_path, auth_mode)

        if token_existed:
            with open(token_path, "wb") as f:
                f.write(token_contents)
            os.chmod(token_path, token_mode)
        elif os.path.exists(token_path):
            os.remove(token_path)

        if os.path.exists(record_path):
            os.remove(record_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
