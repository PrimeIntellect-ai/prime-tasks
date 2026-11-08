#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import stat
import subprocess
import tempfile
import time
import uuid

import pytest
import requests

PROJECT = "/home/user/legacy_audio"
CLI = os.path.join(PROJECT, "build", "hasher_cli")
URL = "http://127.0.0.1:9090/hash"
SEED = "rusted metal"


def test_fuzz_test_script():
    path = "/home/user/fuzz_test.sh"
    assert os.path.isfile(path), f"Fuzz test script {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Fuzz test script {path} is not executable."

    wrapper_dir = tempfile.mkdtemp(prefix="curl_wrapper_")
    log_path = os.path.join(wrapper_dir, "calls.jsonl")
    wrapper = os.path.join(wrapper_dir, "curl")
    with open(wrapper, "w") as f:
        f.write(r'''#!/usr/bin/python3
import json
import os
import sys

args = sys.argv[1:]
payload = None
url = None
i = 0
while i < len(args):
    arg = args[i]
    if arg in ("-d", "--data", "--data-raw", "--data-binary", "--data-ascii") and i + 1 < len(args):
        payload = args[i + 1]
        i += 1
    elif arg.startswith("--data=") or arg.startswith("--data-raw=") or arg.startswith("--data-binary=") or arg.startswith("--data-ascii="):
        payload = arg.split("=", 1)[1]
    elif arg.startswith("http://") or arg.startswith("https://"):
        url = arg
    i += 1

if payload is not None and payload.startswith("@"):
    try:
        with open(payload[1:], "r") as pf:
            payload = pf.read()
    except OSError:
        pass

with open(os.environ["FUZZ_CURL_LOG"], "a") as log:
    log.write(json.dumps({"args": args, "url": url, "payload": payload}) + "\n")
os.execv("/usr/bin/curl", ["curl"] + args)
''')
    os.chmod(wrapper, 0o755)

    env = os.environ.copy()
    env["PATH"] = wrapper_dir + os.pathsep + env.get("PATH", "")
    env["FUZZ_CURL_LOG"] = log_path
    result = subprocess.run([path], env=env, capture_output=True, text=True, timeout=90)
    assert result.returncode == 0, f"fuzz_test.sh failed:\nstdout={result.stdout}\nstderr={result.stderr}"
    assert os.path.isfile(log_path), "fuzz_test.sh did not invoke curl"

    with open(log_path) as f:
        calls = [json.loads(line) for line in f if line.strip()]
    payload_calls = [c for c in calls if c.get("payload") is not None]
    assert len(payload_calls) == 50, f"Expected exactly 50 payloads, observed {len(payload_calls)}"
    assert all(c.get("url") == URL for c in payload_calls), "All fuzz payloads must be sent to 127.0.0.1:9090/hash"

    valid = []
    invalid = []
    for call in payload_calls:
        payload = call["payload"]
        try:
            parsed = json.loads(payload)
            if isinstance(parsed, dict) and isinstance(parsed.get("transcript"), str):
                valid.append(payload)
            else:
                invalid.append(payload)
        except (json.JSONDecodeError, TypeError):
            invalid.append(payload)
    assert valid, "fuzz_test.sh did not generate any valid transcript JSON payloads"
    assert invalid, "fuzz_test.sh did not generate any invalid JSON payloads"
    assert len(set(c["payload"] for c in payload_calls)) >= 10, "Fuzz payloads are not sufficiently varied"

    with open(path) as f:
        script_content = f.read()
    assert re.search(r"http_code|response_code", script_content, re.I), "fuzz_test.sh does not inspect HTTP status codes"
    assert "200" in script_content and "400" in script_content, "fuzz_test.sh must accept HTTP 200 or HTTP 400"


def test_cmakelists_rpath():
    path = "/home/user/legacy_audio/CMakeLists.txt"
    assert os.path.isfile(path), f"{path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "RPATH" in content.upper(), "CMakeLists.txt does not seem to contain RPATH configurations."

    build_dir = tempfile.mkdtemp(prefix="rpath_build_")
    subprocess.run(["cmake", PROJECT], cwd=build_dir, check=True, capture_output=True, text=True)
    subprocess.run(["cmake", "--build", "."], cwd=build_dir, check=True, capture_output=True, text=True)
    fresh_cli = os.path.join(build_dir, "hasher_cli")
    assert os.path.isfile(fresh_cli) and os.access(fresh_cli, os.X_OK), "CMake did not build hasher_cli"

    dynamic = subprocess.run(["readelf", "-d", fresh_cli], check=True, capture_output=True, text=True).stdout
    rpath_lines = [line for line in dynamic.splitlines() if "RPATH" in line or "RUNPATH" in line]
    assert rpath_lines, "Built hasher_cli has no RPATH/RUNPATH dynamic entry"
    assert any("ORIGIN" in line for line in rpath_lines), "hasher_cli RPATH/RUNPATH is not relative to the executable"

    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    run = subprocess.run([fresh_cli, "rpath probe", SEED], cwd="/tmp", env=env, capture_output=True, text=True)
    assert run.returncode == 0, f"Fresh hasher_cli cannot run without LD_LIBRARY_PATH: {run.stderr}"
    assert run.stdout.strip() == "rpath probe_rusted metal_hashed"


def get_expected_hash(transcript, seed_phrase):
    cli_path = CLI
    if not os.path.isfile(cli_path):
        build_dir = "/tmp/test_build"
        os.makedirs(build_dir, exist_ok=True)
        subprocess.run(["cmake", PROJECT], cwd=build_dir, check=True, capture_output=True)
        subprocess.run(["make"], cwd=build_dir, check=True, capture_output=True)
        cli_path = os.path.join(build_dir, "hasher_cli")

    result = subprocess.run([cli_path, transcript, seed_phrase], capture_output=True, text=True, env={"LD_LIBRARY_PATH": ""})
    assert result.returncode == 0, f"hasher_cli failed: {result.stderr}"
    return result.stdout.strip()


def assert_valid_response(transcript):
    try:
        response = requests.post(URL, json={"transcript": transcript}, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP server: {e}")
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail("Response is not valid JSON")
    assert data.get("status") == "success", "Response JSON missing 'status': 'success'"
    expected_hash = get_expected_hash(transcript, SEED)
    assert data.get("hash") == expected_hash, f"Expected hash '{expected_hash}', got '{data.get('hash')}'"


def test_http_server_valid_json():
    payload = {"transcript": "hello world"}
    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP server: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail("Response is not valid JSON")
    assert data.get("status") == "success", "Response JSON missing 'status': 'success'"
    expected_hash = get_expected_hash("hello world", "rusted metal")
    assert data.get("hash") == expected_hash, f"Expected hash '{expected_hash}', got '{data.get('hash')}'"


def test_http_server_varied_json():
    transcripts = [
        "dynamic-" + secrets.token_hex(12),
        "spaces " + secrets.token_hex(8) + " in text",
        "quote-\"-backslash-\\-" + secrets.token_hex(6),
        "punctuation !?.,:;-" + secrets.token_hex(7),
        secrets.token_hex(20),
    ]
    for transcript in transcripts:
        assert_valid_response(transcript)


def test_http_server_invalid_json():
    payload = '{"transcript": "hello world"'
    headers = {"Content-Type": "application/json"}
    try:
        response = requests.post(URL, data=payload, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP server: {e}")
    assert response.status_code == 400, f"Expected HTTP 400 for malformed JSON, got {response.status_code}"


def test_http_server_varied_malformed_json():
    token = secrets.token_hex(10)
    malformed = [
        '{"transcript":"' + token + '"',
        '{transcript:"' + token + '"}',
        '{"transcript":' + token + '}',
        '["' + token + '",',
        'not-json-' + token,
    ]
    for payload in malformed:
        response = requests.post(URL, data=payload, headers={"Content-Type": "application/json"}, timeout=5)
        assert response.status_code == 400, f"Expected HTTP 400 for malformed payload {payload!r}, got {response.status_code}"


def test_server_actually_invokes_hasher_cli_with_seed():
    assert os.path.isfile(CLI), f"Expected built hasher_cli at {CLI}"
    backup = CLI + ".verifier_backup"
    transcript = "cli-probe-" + uuid.uuid4().hex
    marker = "probe_hash_" + uuid.uuid4().hex
    arg_log = "/tmp/hasher_probe_args_" + uuid.uuid4().hex
    shutil.copy2(CLI, backup)
    try:
        with open(CLI, "w") as f:
            f.write("#!/bin/bash\n")
            f.write("printf '%s\\n' \"$#\" > " + repr(arg_log) + "\n")
            f.write("printf '%s' \"$1\" >> " + repr(arg_log) + "\n")
            f.write("printf '\\n' >> " + repr(arg_log) + "\n")
            f.write("printf '%s' \"$2\" >> " + repr(arg_log) + "\n")
            f.write("printf '\\n' >> " + repr(arg_log) + "\n")
            f.write("printf '%s\\n' " + repr(marker) + "\n")
        os.chmod(CLI, 0o755)

        response = requests.post(URL, json={"transcript": transcript}, timeout=5)
        assert response.status_code == 200, f"Expected HTTP 200 from CLI probe, got {response.status_code}"
        data = response.json()
        assert data.get("status") == "success"
        assert data.get("hash") == marker, "Server did not return the output of the installed hasher_cli"
        for _ in range(20):
            if os.path.exists(arg_log):
                break
            time.sleep(0.05)
        assert os.path.exists(arg_log), "Server did not execute /home/user/legacy_audio/build/hasher_cli"
        with open(arg_log) as f:
            lines = f.read().splitlines()
        assert lines == ["2", transcript, SEED], f"hasher_cli received incorrect arguments: {lines!r}"
    finally:
        if os.path.exists(backup):
            shutil.copy2(backup, CLI)
            os.unlink(backup)
        if os.path.exists(arg_log):
            os.unlink(arg_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
