#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import stat
import string
import subprocess
import textwrap
import urllib.error
import urllib.request

import pytest

WORKSPACE = "/home/user/protocol_backend"


def post(body):
    req = urllib.request.Request(
        "http://127.0.0.1:8080/", data=body, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.read()
    except urllib.error.URLError as exc:
        pytest.fail(f"Failed to connect to Nginx on port 8080: {exc}")


def test_make_success_and_binaries_exist():
    lib_path = os.path.join(WORKSPACE, "libproto.so")
    server_path = os.path.join(WORKSPACE, "server")

    assert os.path.isfile(lib_path), f"Shared library {lib_path} does not exist. Did make succeed?"
    assert os.path.isfile(server_path), f"Server binary {server_path} does not exist. Did make succeed?"

    subprocess.run(["make", "clean"], cwd=WORKSPACE, capture_output=True)
    result = subprocess.run(
        ["make"], cwd=WORKSPACE, capture_output=True, text=True
    )

    assert result.returncode == 0, f"make failed with error:\n{result.stderr}"
    assert "multiple definition" not in result.stderr, \
        "Linking error 'multiple definition' still present."


def test_nginx_proxy_works():
    # Preserve the original probe.
    test_string = b"pytest_proxy_test_string_123"
    body = post(test_string)
    assert body == test_string, \
        f"Expected response {test_string}, but got {body}. Proxy or backend is not working correctly."

    # Exercise the live service with verifier-generated, unpredictable bodies of
    # several lengths so a fixed-response service cannot satisfy the test.
    alphabet = string.ascii_letters + string.digits
    lengths = [1, 2, 7, 16, 31, 48, 63, 64, 11, 29, 53, 5]
    for length in lengths:
        value = "".join(secrets.choice(alphabet) for _ in range(length)).encode()
        response = post(value)
        assert response == value, \
            f"Expected response {value!r}, but got {response!r}. Proxy/backend did not echo a dynamic body."


def test_prop_test_script():
    script_path = os.path.join(WORKSPACE, "prop_test.sh")

    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    # Preserve the original end-to-end execution and assertions.
    result = subprocess.run(
        [script_path], capture_output=True, text=True, timeout=120
    )
    assert result.returncode == 0, \
        f"prop_test.sh failed with exit code {result.returncode}.\nOutput: {result.stdout}\nError: {result.stderr}"
    assert "PASS: ALL" in result.stdout, \
        f"prop_test.sh did not print 'PASS: ALL'.\nOutput: {result.stdout}"

    # Instrument curl for a second execution. The replacement records every
    # request and echoes its supplied body, allowing the verifier to establish
    # that the script itself performs 100 POSTs with generated test values.
    curl_path = "/usr/bin/curl"
    curl_log = "/tmp/prop_test_curl_calls.jsonl"
    original_curl = open(curl_path, "rb").read()
    original_mode = stat.S_IMODE(os.stat(curl_path).st_mode)

    wrapper = textwrap.dedent(r'''\
        #!/usr/bin/python3
        import fcntl
        import json
        import os
        import sys

        args = sys.argv[1:]
        body = None
        method = None
        url = None
        data_options = {"-d", "--data", "--data-raw", "--data-binary", "--data-urlencode"}
        i = 0
        while i < len(args):
            arg = args[i]
            if arg in ("-X", "--request") and i + 1 < len(args):
                method = args[i + 1].upper()
                i += 2
                continue
            if arg.startswith("--request="):
                method = arg.split("=", 1)[1].upper()
            elif arg in data_options and i + 1 < len(args):
                body = args[i + 1]
                i += 2
                continue
            elif any(arg.startswith(opt + "=") for opt in data_options if opt.startswith("--")):
                body = arg.split("=", 1)[1]
            elif arg.startswith("-d") and arg != "-d":
                body = arg[2:]
            elif arg.startswith("http://") or arg.startswith("https://"):
                url = arg
            i += 1

        if body is None or url != "http://127.0.0.1:8080/":
            sys.exit(2)
        if method is None:
            method = "POST"
        if method != "POST":
            sys.exit(2)

        if body == "@-":
            body = sys.stdin.read()
        elif body.startswith("@"):
            with open(body[1:], "r") as source:
                body = source.read()

        record = {"method": method, "url": url, "body": body}
        with open(os.environ["PROP_CURL_LOG"], "a") as log:
            fcntl.flock(log, fcntl.LOCK_EX)
            log.write(json.dumps(record) + "\n")
            log.flush()
            fcntl.flock(log, fcntl.LOCK_UN)
        sys.stdout.write(body)
    ''').encode()

    try:
        with open(curl_path, "wb") as curl_file:
            curl_file.write(wrapper)
        os.chmod(curl_path, 0o755)
        try:
            os.unlink(curl_log)
        except FileNotFoundError:
            pass

        env = os.environ.copy()
        env["PROP_CURL_LOG"] = curl_log
        instrumented = subprocess.run(
            [script_path], capture_output=True, text=True, env=env, timeout=120
        )
    finally:
        with open(curl_path, "wb") as curl_file:
            curl_file.write(original_curl)
        os.chmod(curl_path, original_mode)

    assert instrumented.returncode == 0, \
        f"prop_test.sh failed under request instrumentation.\nOutput: {instrumented.stdout}\nError: {instrumented.stderr}"
    assert "PASS: ALL" in instrumented.stdout, \
        f"prop_test.sh did not print 'PASS: ALL'.\nOutput: {instrumented.stdout}"
    assert os.path.isfile(curl_log), "prop_test.sh did not invoke curl."

    with open(curl_log) as log:
        calls = [json.loads(line) for line in log if line.strip()]

    assert len(calls) == 100, \
        f"prop_test.sh must issue exactly 100 curl requests; observed {len(calls)}."
    assert all(call["method"] == "POST" for call in calls), \
        "Every property-test request must use POST."
    assert all(call["url"] == "http://127.0.0.1:8080/" for call in calls), \
        "Every property-test request must target http://127.0.0.1:8080/."

    values = [call["body"] for call in calls]
    assert all(re.fullmatch(r"[A-Za-z0-9]{1,64}", value) for value in values), \
        "Every generated body must be an alphanumeric string between 1 and 64 characters."
    assert len({len(value) for value in values}) > 1, \
        "The generated strings must have varying lengths."
    assert len(set(values)) >= 80, \
        "The script did not generate sufficiently varied random test strings."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
