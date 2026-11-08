#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import resource
import secrets
import stat
import subprocess
import tempfile


def test_redacted_log_content():
    redacted_log_path = "/home/user/app_redacted.log"
    assert os.path.exists(redacted_log_path), f"File {redacted_log_path} does not exist."
    assert os.path.isfile(redacted_log_path), f"Path {redacted_log_path} is not a file."

    with open(redacted_log_path, "r") as f:
        content = f.read()

    assert "AKIA" not in content, "Found 'AKIA' in the redacted log; AWS keys were not fully redacted."
    assert "[REDACTED]" in content, "Did not find '[REDACTED]' in the redacted log."

    expected_content = """System initialized.
User login: [REDACTED] success.
Connecting to backend.
Error: [REDACTED] invalid permissions.
Processing batch 1."""

    assert content.strip() == expected_content.strip(), f"The content of {redacted_log_path} does not match the expected redacted output."


def test_redact_script_behavior():
    script_path = "/home/user/redact.sh"
    input_path = "/home/user/app.log"
    output_path = "/home/user/app_redacted.log"
    assert os.path.exists(script_path), f"File {script_path} does not exist."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."

    with open(input_path, "rb") as f:
        original_input = f.read()
    original_output = None
    if os.path.isfile(output_path):
        with open(output_path, "rb") as f:
            original_output = f.read()

    key1 = "AKIA" + secrets.token_hex(8).upper()
    key2 = "AKIA" + secrets.token_hex(8).upper()
    dynamic_input = f"first={key1}\nunchanged text\nsecond {key2} and again {key1}\n"
    expected = re.sub(r"AKIA[A-Z0-9]{16}", "[REDACTED]", dynamic_input)

    try:
        with open(input_path, "w") as f:
            f.write(dynamic_input)
        if os.path.lexists(output_path):
            os.remove(output_path)

        result = subprocess.run(
            ["/bin/bash", script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, f"redact.sh failed: {result.stderr}"
        assert os.path.isfile(output_path), "redact.sh did not create /home/user/app_redacted.log."
        with open(output_path, "r") as f:
            actual = f.read()
        assert actual == expected, "redact.sh did not correctly redact dynamically generated AWS Access Key IDs."
    finally:
        with open(input_path, "wb") as f:
            f.write(original_input)
        if original_output is None:
            if os.path.lexists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, "wb") as f:
                f.write(original_output)


def test_recovered_password():
    pass_path = "/home/user/recovered_pass.txt"
    assert os.path.exists(pass_path), f"File {pass_path} does not exist."
    assert os.path.isfile(pass_path), f"Path {pass_path} is not a file."

    with open(pass_path, "r") as f:
        content = f.read()

    assert content == "OldSecr3tP4ss!", f"The recovered password in {pass_path} is incorrect. Expected 'OldSecr3tP4ss!' but got '{content}'."

    with open("/home/user/mem.dmp", "r") as f:
        ciphertext = bytes.fromhex(f.read().strip())
    prefix = b"DB_PASS="
    candidate_keys = {ciphertext[i] ^ prefix[i] for i in range(len(prefix))}
    assert len(candidate_keys) == 1, "The memory dump is not consistent with the specified single-byte XOR prefix."
    key = candidate_keys.pop()
    plaintext = bytes(b ^ key for b in ciphertext)
    assert plaintext.startswith(prefix), "The derived plaintext does not begin with DB_PASS=."
    expected_password = plaintext[len(prefix):].decode("utf-8")
    assert content == expected_password, "The recovered password does not match the value derived from mem.dmp."


def test_run_secure_script():
    script_path = "/home/user/run_secure.sh"
    process_path = "/home/user/process.sh"
    assert os.path.exists(script_path), f"File {script_path} does not exist."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."
    assert os.path.isfile(process_path), f"File {process_path} does not exist."
    assert os.access(process_path, os.X_OK), f"File {process_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    # Preserve the original static assertions.
    assert re.search(r"ulimit\s+-n\s+50", content) or re.search(r"ulimit\s+.*50", content), \
        f"The script {script_path} does not appear to restrict open file descriptors to 50 using ulimit."
    assert "env -i" in content, \
        f"The script {script_path} does not appear to use 'env -i' to create an empty environment."
    assert "SECRET_KEY=" in content, \
        f"The script {script_path} does not appear to set the SECRET_KEY environment variable."

    nonce = secrets.token_hex(16)
    secret = "key value;$()-" + secrets.token_hex(12)
    report_path = "/tmp/secure-wrapper-report-" + secrets.token_hex(16) + ".json"
    log_path = "/tmp/input log " + secrets.token_hex(8) + ".txt"
    with open(log_path, "w") as f:
        f.write("probe input\n")

    probe = f'''#!/usr/bin/python3
import json
import os
import resource
import sys
raw = open("/proc/self/environ", "rb").read().split(b"\\0")
inherited = [x.decode("utf-8", "surrogateescape") for x in raw if x]
data = {{
    "nonce": {nonce!r},
    "args": sys.argv[1:],
    "secret": os.environ.get("SECRET_KEY"),
    "inherited_environment": inherited,
    "nofile": list(resource.getrlimit(resource.RLIMIT_NOFILE)),
}}
with open({report_path!r}, "w") as out:
    json.dump(data, out)
'''

    with open(process_path, "w") as f:
        f.write(probe)
    os.chmod(process_path, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                            stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

    try:
        result = subprocess.run(
            ["/bin/bash", script_path, log_path, secret],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, f"run_secure.sh failed: {result.stderr}"
        assert os.path.isfile(report_path), "The wrapper did not execute /home/user/process.sh."
        with open(report_path, "r") as f:
            report = json.load(f)

        assert report.get("nonce") == nonce, "The expected probe process was not executed."
        assert report.get("args") == [log_path], "The wrapper did not pass the log path as the sole process argument."
        assert report.get("secret") == secret, "SECRET_KEY was not passed exactly as the second wrapper argument."
        assert report.get("inherited_environment") == ["SECRET_KEY=" + secret], \
            f"The process environment was not empty except for SECRET_KEY: {report.get('inherited_environment')}"
        assert report.get("nofile", [None])[0] == 50, \
            f"The executed process had an open-file soft limit of {report.get('nofile')} instead of 50."
    finally:
        for path in (report_path, log_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
