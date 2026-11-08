#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import secrets
import string
import subprocess
import tempfile
import requests
import pytest

URL = "http://127.0.0.1:8080/transform"


def rle(payload):
    if not payload:
        return ""
    result = []
    i = 0
    while i < len(payload):
        j = i + 1
        while j < len(payload) and payload[j] == payload[i]:
            j += 1
        result.append(f"{j - i}{payload[i]}")
        i = j
    return "".join(result)


def post_and_check(payload, expected):
    try:
        response = requests.post(URL, data=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to frontend API: {e}")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    assert response.text == expected, f"Transformation incorrect. Expected {expected!r}, got {response.text!r}"


def test_regression_script_exists_and_executable():
    script_path = "/home/user/test.sh"
    assert os.path.isfile(script_path), f"Regression script {script_path} does not exist"
    assert os.access(script_path, os.X_OK), f"Regression script {script_path} is not executable"


def test_regression_script_success():
    script_path = "/home/user/test.sh"
    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Regression script failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"


def test_api_transform_hello_world():
    payload = "Hello World!"
    try:
        response = requests.post(URL, data=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to frontend API: {e}")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    expected_output = "1H1e2l1o1 1W1o1r1l1d1!"
    assert response.text == expected_output, f"Transformation incorrect. Expected '{expected_output}', got '{response.text}'"


def test_api_transform_aabbbc():
    payload = "aabbbc"
    try:
        response = requests.post(URL, data=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to frontend API: {e}")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    expected_output = "2a3b1c"
    assert response.text == expected_output, f"Transformation incorrect. Expected '{expected_output}', got '{response.text}'"


def test_api_transform_sample_in():
    with open("/app/sample_in.txt", "r") as f:
        payload = f.read()
    with open("/app/sample_out_expected.txt", "r") as f:
        expected_output = f.read()
    try:
        response = requests.post(URL, data=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to frontend API: {e}")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    assert response.text == expected_output, f"Transformation incorrect for sample_in.txt. Expected '{expected_output}', got '{response.text}'"


def test_api_transform_hidden_payloads():
    alphabet = string.ascii_letters + string.digits + " !@#$%^&*_-+=,.:;?/"
    rng = secrets.SystemRandom()
    payloads = []
    for _ in range(15):
        chunks = []
        for _ in range(rng.randint(5, 30)):
            ch = rng.choice(alphabet)
            chunks.append(ch * rng.randint(1, 12))
        payloads.append("".join(chunks))

    for payload in payloads:
        post_and_check(payload, rle(payload))


def test_regression_script_really_tests_random_sample():
    script_path = "/home/user/test.sh"
    sample_in = "/app/sample_in.txt"
    sample_out = "/app/sample_out_expected.txt"

    with open(sample_in, "rb") as f:
        original_in = f.read()
    with open(sample_out, "rb") as f:
        original_out = f.read()

    rng = secrets.SystemRandom()
    alphabet = string.ascii_letters + string.digits + " !@#$%^&*_-+="
    chunks = [rng.choice(alphabet) * rng.randint(1, 9) for _ in range(24)]
    payload = "".join(chunks)
    expected = rle(payload)

    with tempfile.TemporaryDirectory() as wrapper_dir:
        log_path = os.path.join(wrapper_dir, "commands.log")
        for command in ("curl", "diff", "cmp"):
            real_command = f"/usr/bin/{command}"
            wrapper = os.path.join(wrapper_dir, command)
            with open(wrapper, "w") as f:
                f.write("#!/bin/sh\n")
                f.write(f"echo {command} >> {log_path!r}\n")
                f.write(f"exec {real_command} \"$@\"\n")
            os.chmod(wrapper, 0o755)

        env = os.environ.copy()
        env["PATH"] = wrapper_dir + os.pathsep + env.get("PATH", "")

        try:
            with open(sample_in, "w") as f:
                f.write(payload)
            with open(sample_out, "w") as f:
                f.write(expected)

            good = subprocess.run([script_path], env=env, capture_output=True, text=True, timeout=15)
            assert good.returncode == 0, (
                "Regression script did not accept a valid hidden sample. "
                f"Stdout: {good.stdout}\nStderr: {good.stderr}"
            )

            with open(sample_out, "w") as f:
                f.write(expected + "-deliberately-wrong")
            bad = subprocess.run([script_path], env=env, capture_output=True, text=True, timeout=15)
            assert bad.returncode == 1, (
                "Regression script must exit 1 when the HTTP response differs from "
                f"sample_out_expected.txt; got {bad.returncode}"
            )

            commands = ""
            if os.path.exists(log_path):
                with open(log_path, "r") as f:
                    commands = f.read()
            with open(script_path, "r", errors="replace") as f:
                active_source = "\n".join(
                    line for line in f if not line.lstrip().startswith("#")
                )

            used_curl = "curl\n" in commands or re.search(
                r"(^|[;&|()\s])(?:/usr/bin/)?curl(?=\s|$)", active_source, re.MULTILINE
            )
            used_compare = (
                "diff\n" in commands
                or "cmp\n" in commands
                or re.search(
                    r"(^|[;&|()\s])(?:/usr/bin/)?(?:diff|cmp)(?=\s|$)",
                    active_source,
                    re.MULTILINE,
                )
            )
            assert used_curl, "Regression script does not use curl to call the frontend"
            assert used_compare, "Regression script does not use diff or cmp for strict comparison"
        finally:
            with open(sample_in, "wb") as f:
                f.write(original_in)
            with open(sample_out, "wb") as f:
                f.write(original_out)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
