#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import base64
import secrets
import pytest


def run_python_script(script_path, args=None):
    command = ["python3", script_path]
    if args:
        command.extend(args)
    try:
        return subprocess.run(
            command,
            cwd="/home/user",
            capture_output=True,
            text=True,
            check=True,
            timeout=5,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Running {script_path} failed with error: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Running {script_path} timed out.")


def test_decoded_payload_content():
    payload_path = "/home/user/decoded_payload.txt"
    assert os.path.exists(payload_path), f"File {payload_path} does not exist."

    expected_payload = '<script src="https://cdn.vulnerable.com/jsonp?callback=alert(document.cookie)"></script>'

    with open(payload_path, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    assert content == expected_payload, f"Content of {payload_path} is incorrect. Expected: {expected_payload}, but got: {content}"


def test_analyze_script_parses_and_decodes_log():
    script_path = "/home/user/analyze.py"
    traffic_path = "/home/user/traffic.log"
    payload_path = "/home/user/decoded_payload.txt"

    assert os.path.isfile(script_path), f"Script {script_path} does not exist or is not a regular file."

    with open(traffic_path, "r", encoding="utf-8") as f:
        original_traffic = f.read()

    original_expected = '<script src="https://cdn.vulnerable.com/jsonp?callback=alert(document.cookie)"></script>'

    # First verify that the script itself regenerates the required result from the supplied log.
    if os.path.exists(payload_path):
        os.remove(payload_path)
    run_python_script(script_path)
    assert os.path.isfile(payload_path), f"Running {script_path} did not create {payload_path}."
    with open(payload_path, "r", encoding="utf-8") as f:
        assert f.read().strip() == original_expected

    # Exercise the parser with a fresh payload so a hardcoded output cannot pass.
    token = secrets.token_hex(12)
    malicious = f'<script src="https://cdn.vulnerable.com/jsonp?callback=console.log(\"audit_{token}\")"></script>'
    distractors = [
        f'<script>alert("benign_{token}")</script>',
        f'<img src=x onerror=console.log("other_{token}")>',
    ]
    encoded = [base64.b64encode(x.encode("utf-8")).decode("ascii") for x in distractors]
    encoded_malicious = base64.b64encode(malicious.encode("utf-8")).decode("ascii")
    synthetic_log = (
        "[2026-01-01 00:00:01] GET /index.html HTTP/1.1\n"
        f"[2026-01-01 00:00:02] GET /search?data={encoded[0]} HTTP/1.1\n"
        f"[2026-01-01 00:00:03] GET /search?data={encoded_malicious} HTTP/1.1\n"
        f"[2026-01-01 00:00:04] GET /search?data={encoded[1]} HTTP/1.1\n"
    )

    try:
        with open(traffic_path, "w", encoding="utf-8") as f:
            f.write(synthetic_log)
        if os.path.exists(payload_path):
            os.remove(payload_path)

        run_python_script(script_path)
        assert os.path.isfile(payload_path), f"Running {script_path} did not create {payload_path}."
        with open(payload_path, "r", encoding="utf-8") as f:
            actual = f.read().strip()
        assert actual == malicious, f"Analyzer did not decode and select the JSONP payload. Expected: {malicious}, but got: {actual}"
    finally:
        with open(traffic_path, "w", encoding="utf-8") as f:
            f.write(original_traffic)
        if os.path.exists(payload_path):
            os.remove(payload_path)
        subprocess.run(["python3", script_path], cwd="/home/user", capture_output=True, text=True, timeout=5)


def test_craft_exploit_script():
    script_path = "/home/user/craft_exploit.py"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."

    test_payloads = [
        "fetch('/steal')",
        f'console.log("audit_{secrets.token_hex(10)}")',
        f"window['probe_{secrets.token_hex(10)}']=document.domain",
    ]

    for test_payload in test_payloads:
        expected_html = f'<script src="https://cdn.vulnerable.com/jsonp?callback={test_payload}"></script>'
        expected_b64 = base64.b64encode(expected_html.encode('utf-8')).decode('utf-8')
        result = run_python_script(script_path, [test_payload])
        output = result.stdout.strip()
        assert output == expected_b64, f"Output of {script_path} is incorrect. Expected: {expected_b64}, but got: {output}"


def test_secure_csp_content():
    csp_path = "/home/user/secure_csp.txt"
    assert os.path.exists(csp_path), f"File {csp_path} does not exist."

    expected_csp = "Content-Security-Policy: default-src 'self'; script-src 'self'; object-src 'none';"

    with open(csp_path, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    assert content == expected_csp, f"Content of {csp_path} is incorrect. Expected: {expected_csp}, but got: {content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
