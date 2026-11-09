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
import os
import random
import re
import secrets
import subprocess

import pytest
import requests


def test_merged_manifest_exists_and_sorted():
    path = "/app/merged_manifest.csv"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, f"File {path} is empty"
    assert lines[0] == "ArtifactID,Name,Version", "Header is missing or incorrect"

    data_lines = lines[1:]
    assert data_lines == sorted(data_lines), "Data rows are not sorted alphabetically"

    content = "\n".join(lines)
    assert "A100,Backend,1.0.0" in content
    assert "A101,Database,1.5.2" in content
    assert "A102,Auth,1.1.1" in content
    assert "A103,Frontend,2.1.0" in content
    assert "A104,Logger,1.0.5" in content
    assert "A105,Cache,3.0.0" in content


def test_final_manifest_exists_and_patched():
    path = "/app/final_manifest.csv"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "r") as f:
        content = f.read().strip()

    expected_content = """ArtifactID,Name,Version
A100,Backend,1.0.0
A101,Database,1.6.0
A102,Auth,1.1.1
A103,Frontend,2.1.0
A104,Logger,1.1.0
A105,Cache,3.0.0"""

    assert content == expected_content, f"Content of {path} does not match expected patched output"


def test_processed_logs_exists_and_not_empty():
    path = "/app/processed_logs.txt"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "r") as f:
        content = f.read().strip()

    assert len(content) > 0, f"File {path} is empty"
    assert content.splitlines() == [
        "ERROR: CODE_12",
        "ERROR: CODE_15",
        "ERROR: CODE_99",
    ], f"Unexpected unique error-code output in {path}"


def test_process_logs_script_is_streaming_and_works_on_generated_input():
    script_path = "/app/process_logs.sh"
    log_path = "/app/release.log"
    output_path = "/app/processed_logs.txt"

    assert os.path.isfile(script_path), f"Missing file: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"

    with open(script_path, "r") as f:
        script = f.read()

    assert re.match(r"^#!.*\b(?:ba)?sh\b", script), "process_logs.sh must be a shell script"
    syntax = subprocess.run(["bash", "-n", script_path], text=True, capture_output=True)
    assert syntax.returncode == 0, f"Invalid shell syntax: {syntax.stderr}"

    code_lines = []
    for line in script.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("#"):
            continue
        code_lines.append(line)
    code = "\n".join(code_lines)

    assert re.search(r"\b(awk|grep|sed|sort|uniq)\b", code), (
        "process_logs.sh must use standard stream-processing tools"
    )
    forbidden = [
        r"\b(?:declare|typeset)\s+-[^\n]*[aA]",
        r"\b(?:mapfile|readarray)\b",
        r"\bread\s+-[^\n]*a\b",
        r"\$\{[^}\n]+\[(?:@|\*)\]\}",
        r"^[ \t]*[A-Za-z_][A-Za-z0-9_]*\[[^]]+\][ \t]*=",
        r"^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*=\([\s\S]*",
        r"\$\([ \t]*cat[ \t]+/app/release\.log[ \t]*\)",
        r"`[ \t]*cat[ \t]+/app/release\.log[ \t]*`",
    ]
    for pattern in forbidden:
        assert not re.search(pattern, code, re.MULTILINE), (
            "process_logs.sh still uses an in-memory array or whole-file capture"
        )

    original_log = open(log_path, "rb").read()
    original_output = open(output_path, "rb").read() if os.path.exists(output_path) else None
    try:
        token = secrets.token_hex(4)
        expected = {f"ERROR: CODE_{token}_{i:06d}" for i in range(1200)}
        generated = []
        for line in expected:
            generated.extend([line, line, line])
        generated.extend(f"INFO: generated message {i}" for i in range(500))
        random.SystemRandom().shuffle(generated)
        with open(log_path, "w") as f:
            f.write("\n".join(generated) + "\n")

        result = subprocess.run(
            [script_path], text=True, capture_output=True, timeout=15
        )
        assert result.returncode == 0, (
            f"process_logs.sh failed with exit code {result.returncode}: {result.stderr}"
        )
        actual = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        assert len(actual) == len(expected), "Output must contain every error exactly once"
        assert set(actual) == expected, "Script did not derive the unique errors from release.log"
    finally:
        with open(log_path, "wb") as f:
            f.write(original_log)
        if original_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, "wb") as f:
                f.write(original_output)


def test_server_auth_success():
    url = "http://127.0.0.1:8080/manifest"
    headers = {"Authorization": "Bearer REL-8492-SEC"}

    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to server at {url}: {e}")

    assert response.status_code == 200, f"Expected status 200 OK, got {response.status_code}"

    with open("/app/final_manifest.csv", "r") as f:
        expected_body = f.read()

    assert response.text.strip() == expected_body.strip(), "Response body does not match /app/final_manifest.csv"


def test_server_auth_missing():
    url = "http://127.0.0.1:8080/manifest"

    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to server at {url}: {e}")

    assert response.status_code == 401, f"Expected status 401 Unauthorized for missing auth, got {response.status_code}"


def test_server_auth_invalid():
    url = "http://127.0.0.1:8080/manifest"
    headers = {"Authorization": "Bearer INVALID-TOKEN"}

    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to server at {url}: {e}")

    assert response.status_code == 401, f"Expected status 401 Unauthorized for invalid auth, got {response.status_code}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
