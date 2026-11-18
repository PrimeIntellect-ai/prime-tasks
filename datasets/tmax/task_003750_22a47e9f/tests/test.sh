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
import secrets
import shlex
import subprocess

import pytest
import requests

PROCESS_SCRIPT = "/app/bash-jaccard-logger-1.0/process_log.sh"
SERVER_SCRIPT = "/home/user/server.sh"
AGG_SCRIPT = "/home/user/aggregate.sh"
LOG_FILE = "/tmp/processed_logs.txt"
URL = "http://127.0.0.1:9090"
AUTH = {"Authorization": "Bearer log-auth-key-881"}


def run_process(left, right):
    result = subprocess.run(
        [PROCESS_SCRIPT, left, right],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, f"Script failed to execute: {result.stderr}"
    return result.stdout.strip()


def score(left, right):
    union = left | right
    if not union:
        return "1.00"
    return f"{len(left & right) / len(union):.2f}"


def read_log_lines():
    if not os.path.isfile(LOG_FILE):
        return []
    with open(LOG_FILE, encoding="utf-8") as handle:
        return handle.read().splitlines()


def test_script_fixed_unicode():
    assert os.path.isfile(PROCESS_SCRIPT), f"Script {PROCESS_SCRIPT} is missing."

    result = subprocess.run(
        [PROCESS_SCRIPT, "D\u00e9fense de stationner", "d\u00e9fense de stationner ici"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Script failed to execute: {result.stderr}"
    output = result.stdout.strip()
    assert output == "0.75", f"Expected script to output 0.75 for unicode inputs, got: {output}"


def test_script_decodes_literal_unicode_escape():
    common = "w" + secrets.token_hex(8)
    other = "w" + secrets.token_hex(8)
    escaped = f"Caf\\u00e9 {common}"
    decoded = f"café {common} {other}"
    assert run_process(escaped, decoded) == "0.67"


def test_script_randomized_jaccard_inputs():
    universe = ["w" + secrets.token_hex(6) for _ in range(12)]
    observed = set()
    for _ in range(7):
        left_count = 1 + secrets.randbelow(8)
        right_count = 1 + secrets.randbelow(8)
        left = set(secrets.SystemRandom().sample(universe, left_count))
        right = set(secrets.SystemRandom().sample(universe, right_count))
        expected = score(left, right)
        observed.add(expected)
        left_text = " ".join(word.upper() + ("," if i % 2 == 0 else "") for i, word in enumerate(sorted(left)))
        right_text = " ".join(word + ("!" if i % 2 else "") for i, word in enumerate(sorted(right)))
        assert run_process(left_text, right_text) == expected
    assert len(observed) >= 2, "Random challenge unexpectedly lacked score diversity"


def test_http_service_artifact():
    assert os.path.isfile(SERVER_SCRIPT), f"Server script {SERVER_SCRIPT} is missing."
    assert os.access(SERVER_SCRIPT, os.X_OK), f"Server script {SERVER_SCRIPT} is not executable."
    with open(SERVER_SCRIPT, encoding="utf-8", errors="replace") as handle:
        first_line = handle.readline()
    assert first_line.startswith("#!") and "bash" in first_line, "server.sh must be a Bash script"


def test_http_service_unauthorized():
    payload = '{"message": "test", "baseline": "test"}\n'
    try:
        response = requests.post(URL, data=payload, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the HTTP service on 127.0.0.1:9090. Is it running?")

    assert response.status_code == 401, f"Expected 401 Unauthorized when missing Auth header, got {response.status_code}"


def test_http_service_rejects_wrong_authorization_without_processing():
    before = read_log_lines()
    marker = "w" + secrets.token_hex(12)
    payload = json.dumps({"message": marker, "baseline": marker}) + "\n"
    response = requests.post(
        URL,
        headers={"Authorization": "Bearer log-auth-key-881-wrong"},
        data=payload,
        timeout=5,
    )
    assert response.status_code == 401
    assert read_log_lines() == before, "Unauthorized input must not be appended to the processed log"


def test_http_service_authorized_and_processing():
    payload = (
        '{"message": "D\\u00e9fense de stationner", "baseline": "d\\u00e9fense de stationner ici"}\n'
        '{"message": "hello world", "baseline": "hello"}\n'
    )

    try:
        response = requests.post(URL, headers=AUTH, data=payload, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the HTTP service on 127.0.0.1:9090. Is it running?")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    lines = response.text.strip().split('\n')
    assert len(lines) == 2, f"Expected 2 lines of output, got {len(lines)}"
    assert lines[0].strip() == "0.75", f"Expected first score to be 0.75, got {lines[0]}"
    assert lines[1].strip() == "0.50", f"Expected second score to be 0.50, got {lines[1]}"


def test_processed_logs_appended():
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} was not created."
    with open(LOG_FILE, "r") as handle:
        content = handle.read()
    assert "0.75" in content, f"Expected 0.75 to be appended to {LOG_FILE}"


def test_http_service_randomized_json_lines_and_exact_append():
    rng = secrets.SystemRandom()
    universe = ["w" + secrets.token_hex(7) for _ in range(14)] + ["café"]
    objects = []
    expected = []

    for index in range(3 + secrets.randbelow(4)):
        left = set(rng.sample(universe, 1 + secrets.randbelow(9)))
        right = set(rng.sample(universe, 1 + secrets.randbelow(9)))
        expected.append(score(left, right))

        def render(words):
            rendered = []
            for i, word in enumerate(sorted(words)):
                value = word if word == "café" else (word.upper() if (i + index) % 2 else word)
                rendered.append(value + ("," if i % 2 else "!"))
            return " ".join(rendered)

        objects.append({"message": render(left), "baseline": render(right)})

    assert len(set(expected)) >= 2 or len(objects) >= 3
    payload = "".join(json.dumps(obj, ensure_ascii=True) + "\n" for obj in objects)
    before = read_log_lines()
    response = requests.post(URL, headers=AUTH, data=payload.encode("utf-8"), timeout=8)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}: {response.text!r}"
    actual = [line.strip() for line in response.text.splitlines()]
    assert actual == expected, f"Expected dynamically computed scores {expected}, got {actual}"

    after = read_log_lines()
    assert after[:len(before)] == before, "The service replaced or modified existing processed scores"
    assert after[len(before):] == expected, f"Expected the request scores to be appended to {LOG_FILE}"


def test_aggregation_script():
    assert os.path.isfile(AGG_SCRIPT), f"Aggregation script {AGG_SCRIPT} is missing."
    assert os.access(AGG_SCRIPT, os.X_OK), f"Aggregation script {AGG_SCRIPT} is not executable."

    with open(LOG_FILE, "w") as handle:
        handle.write("0.75\n0.50\n0.25\n")

    result = subprocess.run([AGG_SCRIPT], capture_output=True, text=True)
    assert result.returncode == 0, f"Aggregation script failed: {result.stderr}"

    out_file = "/tmp/average_sim.txt"
    assert os.path.isfile(out_file), f"Output file {out_file} was not created by aggregation script."
    with open(out_file, "r") as handle:
        avg = handle.read().strip()
    assert avg == "0.50", f"Expected average to be 0.50, got {avg}"


def test_aggregation_script_randomized_values():
    cents = [secrets.randbelow(101) for _ in range(3)]
    cents.append((-sum(cents)) % 4)
    expected_cents = sum(cents) // 4
    values = [f"{value / 100:.2f}" for value in cents]

    with open(LOG_FILE, "w") as handle:
        handle.write("\n".join(values) + "\n")
    if os.path.exists("/tmp/average_sim.txt"):
        os.unlink("/tmp/average_sim.txt")

    result = subprocess.run([AGG_SCRIPT], capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, f"Aggregation script failed: {result.stderr}"
    assert os.path.isfile("/tmp/average_sim.txt")
    with open("/tmp/average_sim.txt", encoding="utf-8") as handle:
        actual = handle.read().strip()
    expected = f"{expected_cents / 100:.2f}"
    assert actual == expected, f"Expected randomized average {expected}, got {actual}"


def test_cron_job_installed():
    result = subprocess.run(["crontab", "-l", "-u", "user"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab for user 'user'."
    assert "/home/user/aggregate.sh" in result.stdout, "Cron job for aggregate.sh is not installed for 'user'."
    assert "* * * * *" in result.stdout, "Cron job is not set to run every minute (* * * * *)."

    valid = False
    for raw_line in result.stdout.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 5)
        if len(parts) != 6 or parts[:5] != ["*"] * 5:
            continue
        try:
            command = shlex.split(parts[5])
        except ValueError:
            continue
        while command and "=" in command[0] and not command[0].startswith("/"):
            command.pop(0)
        if command and command[0] == AGG_SCRIPT:
            valid = True
        elif len(command) >= 2 and os.path.basename(command[0]) in {"bash", "sh"} and command[1] == AGG_SCRIPT:
            valid = True
        elif len(command) >= 3 and os.path.basename(command[0]) == "env" and os.path.basename(command[1]) in {"bash", "sh"} and command[2] == AGG_SCRIPT:
            valid = True
    assert valid, "No active every-minute cron entry actually executes /home/user/aggregate.sh"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
