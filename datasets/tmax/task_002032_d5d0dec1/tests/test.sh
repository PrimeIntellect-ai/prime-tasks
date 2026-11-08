#!/bin/bash
mkdir -p /logs/verifier
reward=0
real_analyzer=/app/analyzer.verifier-real
trace_file=/tmp/analyzer_service_calls.log
rm -f "$real_analyzer" "$trace_file"

prepared=0
if [ -x /app/analyzer ] && mv /app/analyzer "$real_analyzer"; then
    : > "$trace_file"
    chmod 666 "$trace_file"
    cat > /app/analyzer <<'WRAPPER_EOF'
#!/bin/bash
input="$(cat)"
if [ "${VERIFIER_ORACLE_CALL:-}" != "1" ]; then
    printf '%s\t%s\n' "${MATRIX_ENGINE:-}" "$input" >> /tmp/analyzer_service_calls.log
fi
printf '%s\n' "$input" | exec /app/analyzer.verifier-real
WRAPPER_EOF
    if chmod 755 /app/analyzer; then
        prepared=1
    fi
fi

if [ "$prepared" -eq 1 ]; then
cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import secrets
import subprocess

import pytest
import requests

URL = "http://127.0.0.1:5050/process"
HEADERS = {"X-Pipeline-Token": "alpha-etl-883"}
TRACE = "/tmp/analyzer_service_calls.log"
REAL_ANALYZER = "/app/analyzer.verifier-real"


def test_required_artifacts_exist():
    assert os.path.isfile("/home/user/etl_service.py") or os.path.isfile("/home/user/etl_service.sh"), \
        "Expected service code at /home/user/etl_service.py or /home/user/etl_service.sh"
    assert os.path.isfile(REAL_ANALYZER), "Legacy analyzer binary is missing"
    assert os.access(REAL_ANALYZER, os.X_OK), "Legacy analyzer is not executable"
    with open(REAL_ANALYZER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Legacy analyzer is not an ELF binary"


def test_service_running_and_unauthorized_rejected():
    try:
        response = requests.post(URL, data="1.0,2.0,3.0,4.0,5.0", timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not listening on 127.0.0.1:5050")

    assert response.status_code in [401, 403], f"Expected 401 or 403 for missing token, got {response.status_code}"


def test_service_wrong_token_rejected():
    try:
        response = requests.post(URL, headers={"X-Pipeline-Token": "wrong-token"}, data="1.0,2.0,3.0,4.0,5.0", timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not listening on 127.0.0.1:5050")

    assert response.status_code in [401, 403], f"Expected 401 or 403 for wrong token, got {response.status_code}"


def test_service_process_valid_data():
    payload = "1.5,?,5.5,?,9.0"
    try:
        response = requests.post(URL, headers=HEADERS, data=payload, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not listening on 127.0.0.1:5050")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "imputed" in data, "Response JSON missing 'imputed' key"
    assert "score" in data, "Response JSON missing 'score' key"

    expected_imputed = [1.5, 3.5, 5.5, 5.5, 9.0]
    actual_imputed = data["imputed"]

    assert isinstance(actual_imputed, list), "'imputed' should be a list"
    assert len(actual_imputed) == 5, f"Expected 5 imputed values, got {len(actual_imputed)}"

    for expected, actual in zip(expected_imputed, actual_imputed):
        assert math.isclose(expected, actual, rel_tol=1e-5), f"Imputed values mismatch. Expected {expected_imputed}, got {actual_imputed}"

    expected_score = 6.24
    actual_score = data["score"]
    assert isinstance(actual_score, (int, float)), "'score' should be a number"
    assert math.isclose(expected_score, actual_score, rel_tol=1e-2), f"Score mismatch. Expected {expected_score}, got {actual_score}"


def test_service_process_no_missing_data():
    payload = "2.0,4.0,6.0,8.0,10.0"
    try:
        response = requests.post(URL, headers=HEADERS, data=payload, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not listening on 127.0.0.1:5050")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    data = response.json()

    expected_imputed = [2.0, 4.0, 6.0, 8.0, 10.0]
    actual_imputed = data["imputed"]

    for expected, actual in zip(expected_imputed, actual_imputed):
        assert math.isclose(expected, actual, rel_tol=1e-5), f"Imputed values mismatch. Expected {expected_imputed}, got {actual_imputed}"

    expected_score = 7.42
    actual_score = data["score"]
    assert math.isclose(expected_score, actual_score, rel_tol=1e-2), f"Score mismatch. Expected {expected_score}, got {actual_score}"


def reference_means():
    with open("/home/user/reference_data.csv", newline="") as f:
        rows = [[float(value) for value in row] for row in csv.reader(f) if row]
    assert rows and all(len(row) == 5 for row in rows)
    return [sum(row[col] for row in rows) / len(rows) for col in range(5)]


def invoke_analyzer(values):
    analyzer_input = ",".join(format(value, ".17g") for value in values) + "\n"
    env = os.environ.copy()
    env["MATRIX_ENGINE"] = "blas"
    env["VERIFIER_ORACLE_CALL"] = "1"
    result = subprocess.run(
        ["/app/analyzer"], input=analyzer_input, text=True,
        capture_output=True, env=env, timeout=3
    )
    assert result.returncode == 0, f"Independent analyzer invocation failed: {result.stderr}"
    assert result.stdout.strip(), "Independent analyzer invocation produced blank output"
    return float(result.stdout.strip())


def assert_service_invoked_analyzer(expected_values):
    with open(TRACE) as f:
        records = [line.rstrip("\n") for line in f if line.strip()]
    assert records, "The service did not execute /app/analyzer"

    matching = False
    for record in records:
        engine, separator, raw_input = record.partition("\t")
        if not separator or engine != "blas":
            continue
        try:
            sent = [float(part.strip()) for part in raw_input.split(",")]
        except ValueError:
            continue
        if len(sent) == 5 and all(math.isclose(a, b, rel_tol=1e-9, abs_tol=1e-9)
                                  for a, b in zip(sent, expected_values)):
            matching = True
            break
    assert matching, "Service did not pass the imputed values to /app/analyzer with MATRIX_ENGINE=blas"


def test_randomized_requests_are_imputed_and_executed_by_analyzer():
    means = reference_means()
    rng = secrets.SystemRandom()

    for case_index in range(10):
        original = [rng.randint(-150000, 175000) / 100.0 for _ in range(5)]
        if case_index == 0:
            missing = set()
        else:
            missing_count = 1 + rng.randrange(3)
            missing = set(rng.sample(range(5), missing_count))

        expected = [means[i] if i in missing else original[i] for i in range(5)]
        payload = ",".join("?" if i in missing else format(original[i], ".2f") for i in range(5))
        expected_score = invoke_analyzer(expected)

        with open(TRACE, "w"):
            pass
        os.chmod(TRACE, 0o666)

        response = requests.post(URL, headers=HEADERS, data=payload, timeout=5)
        assert response.status_code == 200, \
            f"Expected 200 for randomized payload {payload}, got {response.status_code}: {response.text}"
        try:
            data = response.json()
        except (ValueError, json.JSONDecodeError):
            pytest.fail(f"Response is not valid JSON: {response.text}")

        assert set(("imputed", "score")).issubset(data), "Response must contain imputed and score"
        assert isinstance(data["imputed"], list) and len(data["imputed"]) == 5
        assert all(isinstance(value, (int, float)) for value in data["imputed"])
        assert isinstance(data["score"], (int, float))
        for wanted, actual in zip(expected, data["imputed"]):
            assert math.isclose(wanted, actual, rel_tol=1e-9, abs_tol=1e-9), \
                f"Incorrect dynamic imputation for {payload}: expected {expected}, got {data['imputed']}"
        assert math.isclose(expected_score, data["score"], rel_tol=1e-9, abs_tol=1e-9), \
            f"Score differs from an independent /app/analyzer invocation for {payload}"
        assert_service_invoked_analyzer(expected)
TEST_EOF

    if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
        reward=1
    fi
fi

if [ -e "$real_analyzer" ]; then
    rm -f /app/analyzer
    mv "$real_analyzer" /app/analyzer
fi

echo "$reward" > /logs/verifier/reward.txt
