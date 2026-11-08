#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shlex
import shutil
import subprocess
import tempfile

import pytest
import requests


def expected_lcg(n):
    val = 42
    for _ in range(n):
        val = (val * 13 + 7) % 1000003
    return val


def check_service_response(n):
    url = f"http://127.0.0.1:8080/calc?n={n}"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code} for n={n}."

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from {url} is not valid JSON. Response text: {response.text}")

    assert "result" in data, f"Response JSON missing 'result' key. Got: {data}"

    expected_value = expected_lcg(n)
    assert data["result"] == expected_value, f"Expected result {expected_value} for n={n}, got {data['result']}."


def test_regression_test_script_exists_and_executable():
    path = "/home/user/regression_test.py"
    assert os.path.isfile(path), f"Regression test script {path} does not exist."
    assert os.access(path, os.X_OK), f"Regression test script {path} is not executable."


@pytest.mark.parametrize("n", [0, 1, 10, 50, 100, 1000])
def test_service_responses(n):
    check_service_response(n)


def test_service_responses_on_unpredictable_inputs():
    rng = random.SystemRandom()
    fixed = {0, 1, 10, 50, 100, 1000}
    values = set()
    while len(values) < 24:
        n = rng.randrange(2, 20001)
        if n not in fixed:
            values.add(n)
    for n in values:
        check_service_response(n)


def test_regression_script_runs_full_range_and_detects_mismatch():
    script = "/home/user/regression_test.py"
    legacy = "/app/legacy_calc"
    workdir = tempfile.mkdtemp(prefix="verify_regression_")
    original = os.path.join(workdir, "legacy_calc.original")
    call_log = os.path.join(workdir, "calls.log")
    mutate_n = random.SystemRandom().randrange(0, 51)

    os.replace(legacy, original)

    def install_wrapper(mutation=None):
        mutation_clause = ""
        if mutation is not None:
            mutation_clause = f'''\nif [ "$1" = "{mutation}" ]; then
    printf '%s\\n' "$((out + 1))"
else
    printf '%s\\n' "$out"
fi
'''
        else:
            mutation_clause = '''\nprintf '%s\\n' "$out"
'''

        wrapper = f'''#!/bin/bash
printf '%s\\n' "$1" >> {shlex.quote(call_log)}
out="$({shlex.quote(original)} "$@")" || exit $?
{mutation_clause}'''
        with open(legacy, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.chmod(legacy, 0o755)

    try:
        install_wrapper()
        normal = subprocess.run(
            [script],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=45,
        )
        assert normal.returncode == 0, (
            "Regression script failed on matching legacy/service outputs.\n"
            f"stdout:\n{normal.stdout}\nstderr:\n{normal.stderr}"
        )

        with open(call_log, "r", encoding="utf-8") as f:
            calls = [line.strip() for line in f if line.strip()]
        numeric_calls = set()
        for value in calls:
            try:
                numeric_calls.add(int(value, 10))
            except ValueError:
                pass
        missing = set(range(51)) - numeric_calls
        assert not missing, f"Regression script did not execute legacy_calc for N values: {sorted(missing)}"

        install_wrapper(mutate_n)
        altered = subprocess.run(
            [script],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=45,
        )
        assert altered.returncode != 0, (
            f"Regression script did not detect a deliberately mismatched legacy result for N={mutate_n}."
        )
    finally:
        try:
            if os.path.lexists(legacy):
                os.unlink(legacy)
            os.replace(original, legacy)
        finally:
            shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
