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
import hashlib
import os
import secrets
import socket
import subprocess
import time

import pytest
import requests

CSV_PATH = "/home/user/data/equations.csv"
TSV_PATH = "/home/user/processed/unique_equations.tsv"
PROCESS_SCRIPT = "/home/user/process_math.sh"
BASHTTPD = "/app/bashttpd-0.1/bashttpd"
HANDLERS = "/home/user/server.sh_handlers"


def normalize_equation(eq_text):
    eq_text = "".join(eq_text.split())
    for i in range(10):
        eq_text = eq_text.replace(chr(0xFF10 + i), str(i))
    return eq_text.replace("×", "*")


def get_expected_data():
    assert os.path.isfile(CSV_PATH), f"Missing {CSV_PATH}"
    unique_eqs = {}
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        lines = f.read().strip().split("\n")

    for line in lines[1:]:
        if not line.strip():
            continue
        parts = line.split(",", 1)
        if len(parts) == 2:
            norm = normalize_equation(parts[1])
            h = hashlib.sha256(norm.encode("utf-8")).hexdigest()
            if h not in unique_eqs:
                unique_eqs[h] = norm
    return unique_eqs


def test_process_math_script_exists():
    assert os.path.isfile(PROCESS_SCRIPT), f"Missing {PROCESS_SCRIPT}"
    assert os.access(PROCESS_SCRIPT, os.X_OK), f"Script {PROCESS_SCRIPT} is not executable"


def test_processed_file_content_after_executing_script():
    # Add unpredictable, valid input before executing the submitted pipeline so a
    # precomputed TSV or an empty script cannot pass.
    digits = secrets.randbelow(90000000) + 10000000
    ascii_digits = str(digits)
    fullwidth_digits = "".join(chr(0xFF10 + int(c)) for c in ascii_digits)
    extra = (
        f"\nverify9001, {fullwidth_digits} × ２\n"
        f"verify9002,{ascii_digits}*2\n"
        f"verify9003,９ ＋ {fullwidth_digits} × ３\n"
    )
    with open(CSV_PATH, "a", encoding="utf-8") as f:
        f.write(extra)

    if os.path.exists(TSV_PATH):
        os.remove(TSV_PATH)

    result = subprocess.run(
        [PROCESS_SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{PROCESS_SCRIPT} failed with exit code {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(TSV_PATH), f"Executing {PROCESS_SCRIPT} did not create {TSV_PATH}"

    expected = get_expected_data()
    with open(TSV_PATH, "r", encoding="utf-8") as f:
        lines = f.read().strip().split("\n")

    actual = {}
    for line in lines:
        if not line.strip():
            continue
        parts = line.split("\t")
        assert len(parts) == 2, f"Invalid format in TSV line: {line}"
        actual[parts[0]] = parts[1]

    assert actual == expected, (
        "The processed unique equations do not match the expected deduplicated output."
    )


def test_bashttpd_fixed_and_preserves_query_uri():
    assert os.path.isfile(BASHTTPD), f"File missing: {BASHTTPD}"
    assert os.access(BASHTTPD, os.X_OK), f"Framework is not executable: {BASHTTPD}"
    with open(BASHTTPD, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "REQUEST_URI=$(echo \"$RAW_URI\" | tr -dc 'a-zA-Z0-9/')" not in content, (
        "bashttpd perturbation was not fixed."
    )

    assert os.path.isfile(HANDLERS), f"Missing bashttpd handlers: {HANDLERS}"
    with open(HANDLERS, "rb") as f:
        original_handlers = f.read()

    probe_uri = "/equation?hash=abc-def012&mode=x-y"
    probe_handler = b'''handle_equation() {
  printf 'REQUEST_URI=%s\\nHASH=%s\\n' "$REQUEST_URI" "$1"
}
'''
    try:
        with open(HANDLERS, "wb") as f:
            f.write(probe_handler)
        result = subprocess.run(
            [BASHTTPD],
            input=f"GET {probe_uri} HTTP/1.1\r\nHost: localhost\r\n\r\n",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
    finally:
        with open(HANDLERS, "wb") as f:
            f.write(original_handlers)

    assert result.returncode == 0, f"bashttpd failed when parsing a request: {result.stderr}"
    assert f"REQUEST_URI={probe_uri}" in result.stdout, (
        "bashttpd did not preserve ?, =, &, or - in the request URI"
    )
    assert "HASH=abc-def012" in result.stdout, "bashttpd did not parse the hash query parameter"


def check_responses(base_url):
    expected = get_expected_data()
    assert expected, "No expected data found to test HTTP server."

    for h, eq in expected.items():
        url = f"{base_url}/equation?hash={h}"
        try:
            resp = requests.get(url, timeout=2)
        except requests.exceptions.RequestException as exc:
            pytest.fail(f"Failed to connect to HTTP server at {url}: {exc}")
        assert resp.status_code == 200, f"Expected HTTP 200 for hash {h}, got {resp.status_code}"
        assert resp.text.strip() == eq, f"Expected body '{eq}' for hash {h}, got '{resp.text}'"

    fake_hash = "0" * 64
    url = f"{base_url}/equation?hash={fake_hash}"
    try:
        resp = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to HTTP server at {url}: {exc}")
    assert resp.status_code == 404, f"Expected HTTP 404 for non-existent hash, got {resp.status_code}"


def test_http_server_responses():
    assert os.path.isfile("/home/user/server.sh"), "Missing /home/user/server.sh"
    time.sleep(1)
    # Preserve the original requirement that the agent-started service is active.
    check_responses("http://127.0.0.1:8080")


def test_responses_are_served_through_vendored_bashttpd():
    # Start a verifier-controlled listener whose connection handler is explicitly
    # the submitted vendored framework, preventing an unrelated server from being
    # used to satisfy all HTTP checks.
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]

    listener = subprocess.Popen(
        [
            "socat",
            f"TCP-LISTEN:{port},bind=127.0.0.1,reuseaddr,fork",
            f"EXEC:{BASHTTPD}",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    try:
        time.sleep(0.4)
        assert listener.poll() is None, "Could not start bashttpd test listener"
        check_responses(f"http://127.0.0.1:{port}")
    finally:
        listener.terminate()
        try:
            listener.wait(timeout=2)
        except subprocess.TimeoutExpired:
            listener.kill()
            listener.wait(timeout=2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
