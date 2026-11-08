#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import pytest

PROJECT = "/home/user/project"
SANITIZER = os.path.join(PROJECT, "sanitizer.py")
API_URL = "http://localhost:8000/execute"


def test_venv_dependencies():
    pip_path = "/home/user/project/venv/bin/pip"
    python_path = "/home/user/project/venv/bin/python"
    assert os.path.isfile(pip_path), "Virtual environment pip not found at /home/user/project/venv/bin/pip. Did you create the venv correctly?"
    assert os.path.isfile(python_path), "Virtual environment Python executable is missing"

    res = subprocess.run([pip_path, "freeze"], capture_output=True, text=True)
    assert res.returncode == 0, f"pip freeze failed with error: {res.stderr}"

    installed_packages = {}
    for line in res.stdout.splitlines():
        if "==" in line:
            pkg, ver = line.split("==", 1)
            installed_packages[pkg.lower()] = ver
        elif "@" in line:
            pkg = line.split("@")[0].strip()
            installed_packages[pkg.lower()] = "unknown"

    assert "fastapi" in installed_packages, "FastAPI is not installed in the virtual environment."
    assert "pydantic" in installed_packages, "Pydantic is not installed in the virtual environment."

    compatibility_check = subprocess.run(
        [python_path, "-c", """
from fastapi import FastAPI
from pydantic import BaseModel
from starlette.responses import JSONResponse
class Payload(BaseModel):
    value: int
app = FastAPI()
@app.post('/probe')
async def probe(payload: Payload):
    return JSONResponse([payload.value])
assert Payload(value='3').value == 3
"""],
        capture_output=True,
        text=True,
    )
    assert compatibility_check.returncode == 0, (
        "Installed FastAPI/Pydantic/Starlette versions cannot be imported and used together: "
        + compatibility_check.stderr
    )


def test_transcript():
    transcript_path = "/home/user/project/transcript.txt"
    assert os.path.isfile(transcript_path), f"Transcript file missing at {transcript_path}"

    with open(transcript_path, "r", encoding="utf-8") as f:
        content = f.read().lower()

    keywords = ["fork", "sys", "socket", "nested"]
    missing = [kw for kw in keywords if kw not in content]
    assert not missing, f"Transcript is missing critical keywords extracted from audio: {', '.join(missing)}"

    expected = (
        "The GoLite sanitizer must explicitly block any script containing the keywords "
        "FORK, SYS, or SOCKET. Additionally, reject any script where a SPAWN command is "
        "nested inside another SPAWN block, as this leads to resource exhaustion."
    )
    normalize = lambda s: " ".join(re.findall(r"[a-z0-9]+", s.lower()))
    assert normalize(content) == normalize(expected), "Transcript does not contain the complete audio memo"


def post_script(script, timeout=5):
    req = urllib.request.Request(
        API_URL,
        data=script.encode("utf-8"),
        headers={"Content-Type": "text/plain"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        body = response.read().decode("utf-8")
        return response.status, json.loads(body)


def assert_received(script, expected):
    try:
        status, data = post_script(script)
    except urllib.error.HTTPError as e:
        pytest.fail(f"API returned HTTP error {e.code} for a valid script.")
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to API on localhost:8000. Is the server running? Error: {e.reason}")
    except Exception as e:
        pytest.fail(f"Unexpected error when communicating with the API: {e}")
    assert status == 200, f"Expected HTTP 200, got {status}"
    assert isinstance(data, list), "API response should be a JSON array of received values"
    assert [str(value) for value in data] == expected, f"Incorrect received values: {data!r}"


def test_api_execute():
    server_path = os.path.join(PROJECT, "server.py")
    assert os.path.isfile(server_path), f"Server implementation missing at {server_path}"

    # Retain the original valid request and list assertion.
    original = "CHAN results\nSPAWN func1\nSEND results 42\nRECV results"
    assert_received(original, ["42"])

    # Values and names are generated at verification time, so a fixed response cannot pass.
    c1, c2, unused = ("c_" + secrets.token_hex(6) for _ in range(3))
    v1, v2, ignored = ("v_" + secrets.token_hex(12) for _ in range(3))
    script = "\n".join([
        f"CHAN {c1}",
        f"CHAN {c2}",
        f"CHAN {unused}",
        "SPAWN worker",
        f"SEND {c1} {v1}",
        f"SEND {unused} {ignored}",
        f"SEND {c2} {v2}",
        f"RECV {c2}",
        f"RECV {c1}",
    ])
    assert_received(script, [v2, v1])

    channel = "fifo_" + secrets.token_hex(6)
    values = ["item_" + secrets.token_hex(10) for _ in range(3)]
    fifo_script = "\n".join(
        [f"CHAN {channel}"]
        + [f"SEND {channel} {value}" for value in values]
        + [f"RECV {channel}" for _ in values]
    )
    assert_received(fifo_script, values)

    empty_channel = "empty_" + secrets.token_hex(6)
    started = time.monotonic()
    assert_received(f"CHAN {empty_channel}\nRECV {empty_channel}", [])
    assert time.monotonic() - started < 3.5, "An unfulfilled receive did not time out after approximately 2 seconds"


def run_sanitizer(contents):
    fd, path = tempfile.mkstemp(prefix="golite_" + secrets.token_hex(5) + "_", suffix=".txt")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(contents)
        return subprocess.run(
            ["python3", SANITIZER, path], capture_output=True, text=True, timeout=5
        )
    finally:
        os.unlink(path)


def test_adversarial_corpus():
    assert os.path.isfile(SANITIZER), f"Sanitizer script not found at {SANITIZER}"

    evil_dir = "/app/corpus/evil/"
    clean_dir = "/app/corpus/clean/"
    assert os.path.isdir(evil_dir), "Evil corpus directory is missing"
    assert os.path.isdir(clean_dir), "Clean corpus directory is missing"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    evil_bypassed = []
    for f in evil_files:
        res = subprocess.run(["python3", SANITIZER, f], capture_output=True)
        if res.returncode != 1:
            evil_bypassed.append(os.path.basename(f))

    clean_modified = []
    for f in clean_files:
        res = subprocess.run(["python3", SANITIZER, f], capture_output=True)
        if res.returncode != 0:
            clean_modified.append(os.path.basename(f))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    assert not errors, "Adversarial corpus verification failed:\n" + "\n".join(errors)


def test_sanitizer_on_generated_paths_and_inputs():
    channel = "safe_" + secrets.token_hex(8)
    value = "value_" + secrets.token_hex(12)
    clean_cases = [
        f"CHAN {channel}\nSEND {channel} {value}\nRECV {channel}\n",
        "SPAWN first_worker\nSPAWN second_worker\n",
        f"CHAN {channel}\nSPAWN worker\n",
    ]
    for script in clean_cases:
        result = run_sanitizer(script)
        assert result.returncode == 0, f"Generated clean script was rejected: {result.stderr}"

    marker = secrets.token_hex(10)
    evil_cases = [
        f"CHAN c_{marker}\nFORK process_{marker}\n",
        f"CHAN c_{marker}\nSYS call_{marker}\n",
        f"CHAN c_{marker}\nSOCKET connect_{marker}\n",
        f"SPAWN parent_{marker}\n  SPAWN child_{marker}\n",
    ]
    for script in evil_cases:
        result = run_sanitizer(script)
        assert result.returncode == 1, f"Generated evil script was not rejected: {script!r}"


def assert_api_blocked(script):
    req = urllib.request.Request(
        API_URL,
        data=script.encode("utf-8"),
        headers={"Content-Type": "text/plain"},
        method="POST",
    )
    try:
        urllib.request.urlopen(req, timeout=5)
    except urllib.error.HTTPError as e:
        assert e.code == 400, f"Expected HTTP 400 for evil script, got {e.code}"
        return
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to API while testing sanitizer integration: {e.reason}")
    pytest.fail("API accepted an evil script instead of returning HTTP 400")


def test_api_integrates_sanitizer():
    marker = secrets.token_hex(12)
    assert_api_blocked(f"CHAN c_{marker}\nSEND c_{marker} ok\nSYS op_{marker}\n")
    assert_api_blocked(f"SPAWN parent_{marker}\n  SPAWN child_{marker}\n")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
