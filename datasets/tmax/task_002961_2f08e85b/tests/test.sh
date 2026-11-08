#!/bin/bash
set -e
mkdir -p /logs/verifier

build_ok=1
repo=/app/fin_calc-1.2.0

if [ ! -f "$repo/Makefile" ]; then
    echo "Makefile is missing." >&2
    build_ok=0
fi

if [ "$build_ok" -eq 1 ]; then
    if ! dry_run=$(cd "$repo" && make -n install 2>&1); then
        echo "$dry_run" >&2
        build_ok=0
    elif ! printf '%s\n' "$dry_run" | grep -Eq '(pip3?|python3[[:space:]]+-m[[:space:]]+pip)[[:space:]]+install'; then
        echo "The install target does not run pip install." >&2
        build_ok=0
    elif ! printf '%s\n' "$dry_run" | grep -Eq '(-r|--requirement([=[:space:]]))([[:space:]]*)requirements\.txt'; then
        echo "The install target does not install requirements.txt." >&2
        build_ok=0
    elif printf '%s\n' "$dry_run" | grep -q 'Flaskkkkkk'; then
        echo "The broken dependency remains in the install target." >&2
        build_ok=0
    fi
fi

if [ "$build_ok" -eq 1 ]; then
    if ! (cd "$repo" && timeout 120s make install); then
        echo "make install failed." >&2
        build_ok=0
    fi
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import secrets
from decimal import Decimal

import pytest
import requests

URL = "http://127.0.0.1:8080/variance"
AUTH_HEADER = {"X-Auth-Token": "super-secret-token-99"}


def expected_variance(values):
    dec_data = [Decimal(x) for x in values]
    mean = sum(dec_data) / Decimal(len(dec_data))
    return sum((x - mean) ** Decimal('2') for x in dec_data) / Decimal(len(dec_data))


def make_random_payloads():
    payloads = []
    rng = secrets.SystemRandom()
    for _ in range(10):
        values = []
        for _ in range(rng.randint(3, 8)):
            coefficient = rng.randrange(10**15, 10**20)
            if rng.randrange(2):
                coefficient = -coefficient
            scale = rng.randint(1, 14)
            values.append(format(Decimal(coefficient).scaleb(-scale), 'f'))
        payloads.append(values)
    return payloads


RANDOM_PAYLOADS = make_random_payloads()


def test_server_running_and_unauthorized():
    """Test that the server is running and enforces authentication."""
    try:
        response = requests.post(URL, json={"data": ["1.1", "2.2", "3.3"]}, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Server is not running or not reachable at 127.0.0.1:8080.")

    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}."


def test_precision_calculation():
    """Test that the server uses Decimal for exact precision calculation."""
    payload = {"data": ["1.1", "2.2", "3.3"]}

    try:
        response = requests.post(URL, headers=AUTH_HEADER, json=payload, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Server is not running or not reachable at 127.0.0.1:8080.")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code} with body {response.text}"

    data = response.json()
    assert "variance" in data, f"Expected 'variance' in response, got {data}"

    dec_data = [Decimal(x) for x in payload["data"]]
    mean = sum(dec_data) / Decimal(len(dec_data))
    expected_var = sum((x - mean) ** Decimal('2') for x in dec_data) / Decimal(len(dec_data))

    actual_var = Decimal(data["variance"])
    assert actual_var == expected_var, f"Precision issue: expected {expected_var}, got {actual_var}"


@pytest.mark.parametrize("values", RANDOM_PAYLOADS)
def test_randomized_decimal_precision(values):
    """Exercise precision on unpredictable inputs rather than a fixed example."""
    response = requests.post(
        URL, headers=AUTH_HEADER, json={"data": values}, timeout=5
    )
    assert response.status_code == 200, (
        f"Expected 200 OK for {values}, got {response.status_code} with body {response.text}"
    )
    data = response.json()
    assert "variance" in data, f"Expected 'variance' in response, got {data}"
    expected = expected_variance(values)
    actual = Decimal(data["variance"])
    assert actual == expected, f"Precision issue for {values}: expected {expected}, got {actual}"


def test_corrupted_input_handling():
    """Test that the server gracefully handles corrupted input."""
    payload = {"data": ["1.1", "bad_data", "3.3"]}

    try:
        response = requests.post(URL, headers=AUTH_HEADER, json=payload, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Server is not running or not reachable at 127.0.0.1:8080.")

    assert response.status_code == 400, f"Expected 400 Bad Request, got {response.status_code} with body {response.text}"

    data = response.json()
    assert data.get("error") == "corrupted input", f"Expected error message 'corrupted input', got {data}"


def test_unpredictable_corrupted_input_handling():
    bad_value = secrets.token_hex(12) + "_not-a-number"
    values = RANDOM_PAYLOADS[0][:]
    values.insert(secrets.randbelow(len(values) + 1), bad_value)
    response = requests.post(
        URL, headers=AUTH_HEADER, json={"data": values}, timeout=5
    )
    assert response.status_code == 400, (
        f"Expected 400 Bad Request, got {response.status_code} with body {response.text}"
    )
    assert response.json().get("error") == "corrupted input"
TEST_EOF

if [ "$build_ok" -eq 1 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
