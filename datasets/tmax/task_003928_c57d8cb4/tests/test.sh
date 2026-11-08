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
import secrets
import subprocess
import uuid

import pytest
import requests

URL = "http://127.0.0.1:8080/score"
BIN_PATH = "/app/bin/primer_score"


def post_score(payload):
    try:
        return requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Flask API at {URL}: {e}")


def test_deployment_log_exists():
    log_path = "/home/user/deployment.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read()
        assert "READY" in content, f"Log file {log_path} does not contain 'READY'."


def test_redis_motif_threshold():
    result = subprocess.run(
        ["redis-cli", "GET", "motif_threshold"],
        capture_output=True, text=True
    )
    assert result.returncode == 0, "Failed to run redis-cli GET motif_threshold."
    val = result.stdout.strip()
    assert val == "15", f"Expected motif_threshold in Redis to be '15', but got '{val}'."


def test_flask_api_score_perfect_match():
    response = post_score({"target": "ATGCGTAC", "primer": "ATGC"})
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    data = response.json()
    assert data.get("score") == 4, f"Expected score 4, got {data.get('score')}"
    assert data.get("threshold_met") is False, f"Expected threshold_met to be False, got {data.get('threshold_met')}"


def test_flask_api_score_with_mismatch():
    response = post_score({"target": "ATGCGTAC", "primer": "ATTC"})
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    data = response.json()
    assert data.get("score") == 1, f"Expected score 1, got {data.get('score')}"
    assert data.get("threshold_met") is False, f"Expected threshold_met to be False, got {data.get('threshold_met')}"


def test_flask_api_score_threshold_met():
    response = post_score({"target": "A" * 20, "primer": "A" * 15})
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    data = response.json()
    assert data.get("score") == 15, f"Expected score 15, got {data.get('score')}"
    assert data.get("threshold_met") is True, f"Expected threshold_met to be True, got {data.get('threshold_met')}"


def test_c_binary_compiled():
    assert os.path.isfile(BIN_PATH), f"Compiled binary {BIN_PATH} does not exist."
    assert os.access(BIN_PATH, os.X_OK), f"Binary {BIN_PATH} is not executable."
    with open(BIN_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BIN_PATH} is not a compiled ELF executable."


def test_c_binary_randomized_behavior():
    rng = random.SystemRandom()
    alphabet = "ACGT"
    for _ in range(20):
        primer_len = rng.randint(1, 40)
        primer = "".join(rng.choice(alphabet) for _ in range(primer_len))
        target = "".join(rng.choice(alphabet) for _ in range(primer_len + rng.randint(0, 12)))
        expected = sum(1 if target[i] == primer[i] else -2 for i in range(primer_len))
        result = subprocess.run(
            [BIN_PATH, target, primer], capture_output=True, text=True, timeout=5
        )
        assert result.returncode == 0, f"C engine failed for target={target}, primer={primer}"
        assert result.stdout.strip() == str(expected), (
            f"C engine returned {result.stdout.strip()!r}; expected {expected} "
            f"for target={target}, primer={primer}"
        )


def test_api_invokes_binary_and_reads_redis_dynamically():
    token = uuid.uuid4().hex
    real_path = f"/tmp/primer_score.real.{token}"
    trace_path = f"/tmp/primer_score.trace.{token}"
    rng = random.SystemRandom()
    alphabet = "ACGT"
    primer = "".join(rng.choice(alphabet) for _ in range(rng.randint(8, 24)))
    target = "".join(rng.choice(alphabet) for _ in range(len(primer) + 5))
    sentinel = rng.randint(30, 80)

    os.replace(BIN_PATH, real_path)
    try:
        wrapper = (
            "#!/bin/sh\n"
            f"printf '%s\\0%s\\0' \"$1\" \"$2\" >> '{trace_path}'\n"
            f"printf '%s\\n' '{sentinel}'\n"
        )
        with open(BIN_PATH, "w") as f:
            f.write(wrapper)
        os.chmod(BIN_PATH, 0o755)

        set_high = subprocess.run(
            ["redis-cli", "SET", "motif_threshold", str(sentinel + 1)],
            capture_output=True, text=True
        )
        assert set_high.returncode == 0
        response = post_score({"target": target, "primer": primer})
        assert response.status_code == 200
        data = response.json()
        assert data.get("score") == sentinel, "API did not use stdout from /app/bin/primer_score"
        assert data.get("threshold_met") is False, "API did not use the current Redis threshold"

        set_equal = subprocess.run(
            ["redis-cli", "SET", "motif_threshold", str(sentinel)],
            capture_output=True, text=True
        )
        assert set_equal.returncode == 0
        response = post_score({"target": target, "primer": primer})
        assert response.status_code == 200
        data = response.json()
        assert data.get("score") == sentinel, "API did not use stdout from /app/bin/primer_score"
        assert data.get("threshold_met") is True, "API did not observe the updated Redis threshold"

        with open(trace_path, "rb") as f:
            trace = f.read()
        expected_call = target.encode() + b"\0" + primer.encode() + b"\0"
        assert trace == expected_call * 2, (
            "API did not invoke /app/bin/primer_score with the submitted target and primer"
        )
    finally:
        subprocess.run(["redis-cli", "SET", "motif_threshold", "15"], capture_output=True)
        if os.path.exists(BIN_PATH):
            os.remove(BIN_PATH)
        if os.path.exists(real_path):
            os.replace(real_path, BIN_PATH)
        if os.path.exists(trace_path):
            os.remove(trace_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
