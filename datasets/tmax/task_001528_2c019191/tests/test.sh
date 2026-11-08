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

import pytest
import requests
import secrets
import time
from fractions import Fraction

PORT = 9090
URL = f"http://127.0.0.1:{PORT}/"
TOKEN = "PERF_BASH_88X"

def wait_for_service():
    """Wait for the socat service to be available."""
    for _ in range(10):
        try:
            requests.get(URL, timeout=1)
            return True
        except requests.exceptions.ConnectionError:
            time.sleep(0.5)
        except requests.exceptions.ReadTimeout:
            # If it times out, it might be up but not responding properly, which is fine for the check
            return True
    return False

@pytest.fixture(scope="session", autouse=True)
def ensure_service_up():
    assert wait_for_service(), f"Service is not listening on port {PORT}."

def test_no_auth_returns_401():
    try:
        response = requests.get(URL, timeout=2)
    except Exception as e:
        pytest.fail(f"Request failed: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized without auth, got {response.status_code}"

def test_invalid_auth_returns_401():
    headers = {"Authorization": "Bearer WRONG_TOKEN"}
    try:
        response = requests.get(URL, headers=headers, timeout=2)
    except Exception as e:
        pytest.fail(f"Request failed: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized with invalid auth, got {response.status_code}"

def test_valid_auth_and_payload_returns_correct_average():
    headers = {"Authorization": f"Bearer {TOKEN}"}
    payload = "/login,45ms\n/home, 120 ms\n/api/data,85.5\n/api/data, 100"

    try:
        response = requests.post(URL, headers=headers, data=payload, timeout=2)
    except Exception as e:
        pytest.fail(f"Request failed: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except Exception:
        pytest.fail(f"Expected JSON response, got: {response.text}")

    assert "average" in data, "JSON response missing 'average' key"
    assert data["average"] == 88, f"Expected average to be 88, got {data['average']}"

def test_valid_auth_and_different_payload():
    headers = {"Authorization": f"Bearer {TOKEN}"}
    payload = "/a,10\n/b, 20.4 \n/c,30 ms"

    try:
        response = requests.post(URL, headers=headers, data=payload, timeout=2)
    except Exception as e:
        pytest.fail(f"Request failed: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except Exception:
        pytest.fail(f"Expected JSON response, got: {response.text}")

    assert "average" in data, "JSON response missing 'average' key"
    assert data["average"] == 20, f"Expected average to be 20, got {data['average']}"


def make_random_case():
    rng = secrets.SystemRandom()
    while True:
        records = []
        values_in_tenths = []
        styles = ["integer", "integer_ms", "integer_spaced_ms",
                  "decimal", "decimal_spaced", "decimal_ms"]
        rng.shuffle(styles)

        for style in styles:
            endpoint = f"/{secrets.token_hex(8)}/{secrets.token_hex(5)}"
            if style.startswith("integer"):
                integer_value = rng.randint(1, 500)
                tenths = integer_value * 10
                if style == "integer":
                    rendered = str(integer_value)
                elif style == "integer_ms":
                    rendered = f"{integer_value}ms"
                else:
                    left = " " * rng.randint(1, 5)
                    middle = " " * rng.randint(1, 5)
                    right = " " * rng.randint(0, 4)
                    rendered = f"{left}{integer_value}{middle}ms{right}"
            else:
                tenths = rng.randint(11, 5000)
                if tenths % 10 == 0:
                    tenths += rng.randint(1, 9)
                decimal_value = f"{tenths // 10}.{tenths % 10}"
                if style == "decimal":
                    rendered = decimal_value
                elif style == "decimal_spaced":
                    rendered = f"{' ' * rng.randint(1, 5)}{decimal_value}{' ' * rng.randint(1, 5)}"
                else:
                    rendered = f"{' ' * rng.randint(0, 4)}{decimal_value}{' ' * rng.randint(0, 4)}ms{' ' * rng.randint(0, 4)}"

            records.append(f"{endpoint},{rendered}")
            values_in_tenths.append(tenths)

        exact_average = Fraction(sum(values_in_tenths), 10 * len(values_in_tenths))
        whole, remainder = divmod(exact_average.numerator, exact_average.denominator)
        # Avoid an exactly-halfway case so the unspecified tie-breaking convention
        # cannot affect the result.
        if 2 * remainder == exact_average.denominator:
            continue
        expected = whole + int(2 * remainder > exact_average.denominator)
        if expected not in (20, 88):
            return "\n".join(records), expected


def test_randomized_general_metric_processing():
    headers = {"Authorization": f"Bearer {TOKEN}"}

    # Runtime-generated endpoints, values, spacing, and unit forms prevent a
    # handler from recognizing the two fixed examples and returning constants.
    for _ in range(6):
        payload, expected = make_random_case()
        try:
            response = requests.post(URL, headers=headers, data=payload, timeout=2)
        except Exception as e:
            pytest.fail(f"Randomized request failed: {e}")

        assert response.status_code == 200, (
            f"Expected 200 OK for randomized payload, got {response.status_code}. "
            f"Response: {response.text}"
        )
        try:
            data = response.json()
        except Exception:
            pytest.fail(f"Expected JSON response for randomized payload, got: {response.text}")

        assert "average" in data, "JSON response missing 'average' key"
        assert data["average"] == expected, (
            f"Expected randomized average {expected}, got {data['average']}; "
            f"payload was {payload!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
