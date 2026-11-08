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
import json
import subprocess
import secrets
import pytest
import requests
from collections import defaultdict

RAW_LOGS_PATH = "/home/user/raw_logs.tsv"
TOP_ERRORS_PATH = "/home/user/top_errors.txt"
STRATIFIED_ERRORS_PATH = "/home/user/stratified_errors.tsv"
INSTALLED_SCRIPT_PATH = "/home/user/bin/stratify_errors"
SERVER_URL = "http://127.0.0.1:9090"


def derive_expected(lines):
    error_counts = defaultdict(int)
    stratified_lines = []
    stratified_counts = defaultdict(int)

    for line in lines:
        clean = line.rstrip('\n')
        parts = clean.split('\t')
        if len(parts) < 5:
            continue
        endpoint = parts[3]
        try:
            status = int(parts[4])
        except ValueError:
            continue

        if status >= 400:
            error_counts[endpoint] += 1
            if stratified_counts[endpoint] < 2:
                stratified_lines.append(clean)
                stratified_counts[endpoint] += 1

    sorted_endpoints = sorted(error_counts.items(), key=lambda x: x[1], reverse=True)
    top_5 = [ep for ep, count in sorted_endpoints[:5]]
    return top_5, stratified_lines, error_counts


def get_expected_data():
    """Derive expected top errors and stratified errors from the raw logs."""
    if not os.path.exists(RAW_LOGS_PATH):
        return [], [], defaultdict(int)
    with open(RAW_LOGS_PATH, "r") as f:
        return derive_expected(f.readlines())


def run_tool(input_text):
    result = subprocess.run(
        [INSTALLED_SCRIPT_PATH],
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"Installed stratify_errors exited with {result.returncode}. "
        f"stderr: {result.stderr}"
    )
    return result.stdout.splitlines()


def assert_valid_top_list(actual_endpoints, error_counts):
    assert len(actual_endpoints) == 5
    assert len(set(actual_endpoints)) == 5, "Top-error endpoint arrays must not contain duplicates."
    assert all(ep in error_counts for ep in actual_endpoints), "Top-error output contains an unknown endpoint."

    actual_counts = [error_counts[ep] for ep in actual_endpoints]
    assert actual_counts == sorted(actual_counts, reverse=True), (
        "Top-error endpoints are not sorted by frequency descending."
    )

    all_counts = sorted(error_counts.values(), reverse=True)
    cutoff = all_counts[4]
    required = {ep for ep, count in error_counts.items() if count > cutoff}
    assert required.issubset(set(actual_endpoints)), "A required higher-frequency endpoint is missing."
    assert all(error_counts[ep] >= cutoff for ep in actual_endpoints), (
        "Top-error output contains an endpoint below the top-five frequency cutoff."
    )


def test_script_installed_and_fixed():
    """Verify the script is installed, fixed, and actually processes full streams."""
    assert os.path.isfile(INSTALLED_SCRIPT_PATH), f"Installed script {INSTALLED_SCRIPT_PATH} is missing. Did you run make install?"
    assert os.access(INSTALLED_SCRIPT_PATH, os.X_OK), f"Installed script {INSTALLED_SCRIPT_PATH} is not executable."

    with open(INSTALLED_SCRIPT_PATH, "r") as f:
        content = f.read()

    assert "NR>10" not in content.replace(" ", ""), "The deliberate perturbation 'NR>10' is still present in the installed script."

    with open(RAW_LOGS_PATH, "r") as f:
        raw_input = f.read()
    _, expected_raw, _ = derive_expected(raw_input.splitlines(True))
    assert run_tool(raw_input) == expected_raw, (
        "Installed stratify_errors does not produce the required sample for raw_logs.tsv."
    )

    token = secrets.token_hex(8)
    generated = []
    for i in range(1, 31):
        endpoint = f"/generated-{token}-{i % 4}"
        status = 200 if i % 7 == 0 else (400 + (i % 5))
        generated.append(f"{1800000000+i}\t10.1.0.{i}\tGET\t{endpoint}\t{status}\t{i}\n")
    for i in range(31, 36):
        generated.append(f"{1800000000+i}\t10.1.1.{i}\tPOST\t/late-{token}\t503\t0\n")

    generated_input = "".join(generated)
    _, expected_generated, _ = derive_expected(generated)
    assert run_tool(generated_input) == expected_generated, (
        "Installed stratify_errors failed a full-stream input with errors after line 10."
    )


def test_top_errors_file():
    """Verify the top_errors.txt file contains five distinct valid top endpoints."""
    assert os.path.isfile(TOP_ERRORS_PATH), f"{TOP_ERRORS_PATH} is missing."

    top_5, _, error_counts = get_expected_data()

    with open(TOP_ERRORS_PATH, "r") as f:
        actual_endpoints = [line.strip() for line in f if line.strip()]

    assert len(actual_endpoints) == 5, f"Expected exactly 5 endpoints in {TOP_ERRORS_PATH}, found {len(actual_endpoints)}."

    expected_freqs = sorted([error_counts[ep] for ep in top_5], reverse=True)
    actual_freqs = sorted([error_counts.get(ep, 0) for ep in actual_endpoints], reverse=True)
    assert actual_freqs == expected_freqs, f"Top 5 endpoints in {TOP_ERRORS_PATH} do not match the expected frequencies."
    assert_valid_top_list(actual_endpoints, error_counts)


def test_stratified_errors_file():
    """Verify the stratified_errors.tsv file contains exactly 2 logs per error endpoint."""
    assert os.path.isfile(STRATIFIED_ERRORS_PATH), f"{STRATIFIED_ERRORS_PATH} is missing."

    _, expected_stratified, _ = get_expected_data()

    with open(STRATIFIED_ERRORS_PATH, "r") as f:
        actual_stratified = [line.strip('\n') for line in f if line.strip('\n')]

    assert sorted(actual_stratified) == sorted(expected_stratified), f"Contents of {STRATIFIED_ERRORS_PATH} do not match the expected stratified output."


def test_http_server_health():
    """Verify the HTTP server responds to /health with 'OK'."""
    try:
        response = requests.get(f"{SERVER_URL}/health", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP server at {SERVER_URL}/health: {e}")

    assert response.status_code == 200, f"Expected status code 200 for /health, got {response.status_code}"
    assert response.text.strip() == "OK", f"Expected body 'OK' for /health, got {response.text}"


def test_http_server_top_errors():
    """Verify the HTTP server exposes the same distinct top-five list as the output file."""
    try:
        response = requests.get(f"{SERVER_URL}/top-errors", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP server at {SERVER_URL}/top-errors: {e}")

    assert response.status_code == 200, f"Expected status code 200 for /top-errors, got {response.status_code}"

    try:
        actual_json = response.json()
    except ValueError:
        pytest.fail(f"Response from /top-errors is not valid JSON. Body: {response.text}")

    assert isinstance(actual_json, list), "Expected a JSON array for /top-errors."
    assert len(actual_json) == 5, f"Expected exactly 5 elements in the JSON array, got {len(actual_json)}."

    top_5, _, error_counts = get_expected_data()
    expected_freqs = sorted([error_counts[ep] for ep in top_5], reverse=True)
    actual_freqs = sorted([error_counts.get(ep, 0) for ep in actual_json], reverse=True)
    assert actual_freqs == expected_freqs, f"JSON array from /top-errors does not contain the correct top 5 endpoints. Got: {actual_json}"
    assert all(isinstance(ep, str) for ep in actual_json), "Every JSON array element must be an endpoint string."
    assert_valid_top_list(actual_json, error_counts)

    with open(TOP_ERRORS_PATH, "r") as f:
        file_endpoints = [line.strip() for line in f if line.strip()]
    assert actual_json == file_endpoints, (
        "/top-errors must expose the same ordered endpoint list saved in top_errors.txt."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
