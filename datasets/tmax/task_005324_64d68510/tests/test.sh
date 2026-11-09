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
import hashlib
import requests
import pytest


def get_md5(text: str) -> str:
    return hashlib.md5(text.encode("utf-8")).hexdigest()


def test_output_files_exist_and_deduplication_is_global():
    expected_files = [
        "/app/output/en/WELCOME_MSG.txt",
        "/app/output/es/ERR_01.txt",
    ]
    for path in expected_files:
        assert os.path.exists(path), f"Expected output file missing: {path}"
        assert os.path.isfile(path), f"Expected output path is not a file: {path}"

    unexpected_files = [
        "/app/output/es/WELCOME_MSG.txt",
        "/app/output/es/WELCOME_ALT.txt",
    ]
    for path in unexpected_files:
        assert not os.path.exists(path), f"Unexpected duplicate output exists: {path}"


def test_output_file_content():
    expected_contents = {
        "/app/output/en/WELCOME_MSG.txt": (
            "Release: v7.4.2-RCO\n"
            "Locale: en\n"
            "String ID: WELCOME_MSG\n"
            "\n"
            "Welcome to the app!"
        ),
        "/app/output/es/ERR_01.txt": (
            "Release: v7.4.2-RCO\n"
            "Locale: es\n"
            "String ID: ERR_01\n"
            "\n"
            "Archivo\n"
            "no encontrado"
        ),
    }

    for path, expected_content in expected_contents.items():
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
        assert content.strip() == expected_content.strip(), (
            f"Content of {path} does not match expected templated output."
        )


def test_pipeline_log():
    path = "/app/pipeline.log"
    assert os.path.exists(path), f"Missing log file: {path}"

    with open(path, "r", encoding="utf-8") as f:
        log_content = f.read()

    hash_welcome = get_md5("Welcome to the app!")
    hash_err = get_md5("File not found")

    expected_logs = [
        f"[PROCESS] Created template for en - WELCOME_MSG (Hash: {hash_welcome})",
        f"[PROCESS] Created template for es - ERR_01 (Hash: {hash_err})",
    ]
    forbidden_logs = [
        f"[PROCESS] Created template for es - WELCOME_MSG (Hash: {hash_welcome})",
        f"[PROCESS] Created template for es - WELCOME_ALT (Hash: {hash_welcome})",
    ]

    for expected in expected_logs:
        assert expected in log_content, f"Expected log entry not found: {expected}"
    for forbidden in forbidden_logs:
        assert forbidden not in log_content, f"Duplicate row was incorrectly logged: {forbidden}"


def test_http_server_serving_files():
    url = "http://127.0.0.1:9090/es/ERR_01.txt"
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP server at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"

    expected_content = (
        "Release: v7.4.2-RCO\n"
        "Locale: es\n"
        "String ID: ERR_01\n"
        "\n"
        "Archivo\n"
        "no encontrado"
    )
    assert response.text.strip() == expected_content.strip(), (
        "HTTP response content does not match expected output file content."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
