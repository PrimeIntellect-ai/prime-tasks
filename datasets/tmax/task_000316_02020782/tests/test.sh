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
# test_final_state.py
import math
import secrets
import string
import requests
import pytest

def get_expected_d1_d2(text: str):
    S = sum(ord(c) for c in text)
    floats = [(S * (i + 1)) % 100 / 100.0 for i in range(20)]
    d1 = sum(floats[:10]) / 10.0
    d2 = sum(floats[10:]) / 10.0
    return d1, d2

def get_stats(d1_list):
    n = len(d1_list)
    if n < 2:
        return 0.0, 0.0, 0.0
    mean = sum(d1_list) / n
    variance = sum((x - mean) ** 2 for x in d1_list) / (n - 1)
    std_dev = math.sqrt(variance)
    margin = 1.96 * std_dev / math.sqrt(n)
    return mean, mean - margin, mean + margin

def test_api_process_and_stats():
    base_url = "http://127.0.0.1:9000"

    # Preserve the original cases and add unpredictable runtime-generated cases
    # so a fixed response table cannot satisfy /process or /stats.
    alphabet = string.ascii_letters + string.digits + " _-.,!?@#$%^&*()"
    random_words = [
        "runtime-" + "".join(secrets.choice(alphabet) for _ in range(length))
        for length in (1, 3, 7, 11, 16, 23, 31, 42, 57, 73, 91, 127)
    ]
    words = ["hello", "world", "agent", "pytest", "golang"] + random_words
    expected_d1_list = []

    for word in words:
        resp = requests.post(f"{base_url}/process", json={"text": word}, timeout=5)
        assert resp.status_code == 200, f"Expected status 200 for POST /process, got {resp.status_code}"

        data = resp.json()
        assert "reduced_vector" in data, "Response JSON missing 'reduced_vector' key"

        d1, d2 = data["reduced_vector"]
        exp_d1, exp_d2 = get_expected_d1_d2(word)

        assert math.isclose(d1, exp_d1, abs_tol=1e-3), f"For '{word}', expected D1 ~ {exp_d1}, got {d1}"
        assert math.isclose(d2, exp_d2, abs_tol=1e-3), f"For '{word}', expected D2 ~ {exp_d2}, got {d2}"

        expected_d1_list.append(exp_d1)

    # Now check stats against values independently derived from the inputs.
    resp = requests.get(f"{base_url}/stats", timeout=5)
    assert resp.status_code == 200, f"Expected status 200 for GET /stats, got {resp.status_code}"

    data = resp.json()
    assert "mean_d1" in data, "Response JSON missing 'mean_d1' key"
    assert "ci_lower" in data, "Response JSON missing 'ci_lower' key"
    assert "ci_upper" in data, "Response JSON missing 'ci_upper' key"

    exp_mean, exp_lower, exp_upper = get_stats(expected_d1_list)

    assert math.isclose(data["mean_d1"], exp_mean, abs_tol=1e-3), f"Expected mean_d1 ~ {exp_mean}, got {data['mean_d1']}"
    assert math.isclose(data["ci_lower"], exp_lower, abs_tol=1e-3), f"Expected ci_lower ~ {exp_lower}, got {data['ci_lower']}"
    assert math.isclose(data["ci_upper"], exp_upper, abs_tol=1e-3), f"Expected ci_upper ~ {exp_upper}, got {data['ci_upper']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
