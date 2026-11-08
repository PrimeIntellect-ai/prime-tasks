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
mkdir -p /logs/verifier

RACE_TEST=$(mktemp --suffix=_test.go /home/user/math_server/verifier_race_XXXXXX)
cat > "$RACE_TEST" <<'GO_TEST_EOF'
package main

import (
    "reflect"
    "sync"
    "testing"
)

func verifierExpectedFactors(n int) []int {
    out := []int{}
    for d := 2; d*d <= n; d++ {
        for n%d == 0 {
            out = append(out, d)
            n /= d
        }
    }
    if n > 1 {
        out = append(out, n)
    }
    return out
}

func TestVerifierPrimeFactorsConcurrent(t *testing.T) {
    inputs := []int{1, 2, 3, 4, 6, 8, 9, 12, 25, 49, 97, 315, 1024, 1729, 99991, 510510, 1048575}
    failures := make(chan string, 128)
    var wg sync.WaitGroup
    for worker := 0; worker < 64; worker++ {
        wg.Add(1)
        go func(offset int) {
            defer wg.Done()
            for round := 0; round < 50; round++ {
                n := inputs[(offset+round)%len(inputs)]
                got := primeFactors(n)
                want := verifierExpectedFactors(n)
                if !reflect.DeepEqual(got, want) {
                    failures <- "primeFactors returned an incorrect result"
                    return
                }
            }
        }(worker)
    }
    wg.Wait()
    close(failures)
    for failure := range failures {
        t.Fatal(failure)
    }
}
GO_TEST_EOF

race_ok=0
if (cd /home/user/math_server && timeout 90s env GO111MODULE=off go test -race -count=1); then
    race_ok=1
fi
rm -f "$RACE_TEST"

cat <<'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import random

import pytest
import requests

URL = "http://127.0.0.1:9000/prime_factors"
AUTH_HEADER = {"Authorization": "Bearer 84295"}
PAYLOAD = {"number": 315}
EXPECTED_FACTORS = [3, 3, 5, 7]


def expected_factors(number):
    factors = []
    divisor = 2
    while divisor * divisor <= number:
        while number % divisor == 0:
            factors.append(divisor)
            number //= divisor
        divisor += 1
    if number > 1:
        factors.append(number)
    return factors


def checked_request(number, timeout=5):
    response = requests.post(
        URL, headers=AUTH_HEADER, json={"number": number}, timeout=timeout
    )
    assert response.status_code == 200, f"Expected 200 OK for {number}, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Invalid JSON for {number}: {response.text}")
    assert "factors" in data, "Response JSON missing 'factors' key"
    actual = sorted(data["factors"])
    expected = expected_factors(number)
    assert actual == expected, f"Expected factors {expected} for {number}, got {actual}"


def test_server_running_and_auth_required():
    try:
        response = requests.post(URL, json=PAYLOAD, timeout=2)
        assert response.status_code in (401, 403), (
            f"Expected 401 or 403 when missing auth, got {response.status_code}"
        )
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")


def test_correct_prime_factors():
    try:
        response = requests.post(URL, headers=AUTH_HEADER, json=PAYLOAD, timeout=2)
        assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
        data = response.json()
        assert "factors" in data, "Response JSON missing 'factors' key"
        factors = sorted(data["factors"])
        assert factors == EXPECTED_FACTORS, f"Expected factors {EXPECTED_FACTORS}, got {factors}"
    except requests.RequestException as e:
        pytest.fail(f"Request failed: {e}")
    except ValueError:
        pytest.fail(f"Failed to parse JSON response: {response.text}")


def test_general_prime_factorization():
    rng = random.SystemRandom()
    numbers = [1, 2, 4, 8, 49, 97, 1024, 1729, 99991, 510510]
    numbers.extend(rng.randint(2, 2_000_000) for _ in range(25))
    for number in numbers:
        checked_request(number)


def test_concurrency_no_data_race():
    def make_request():
        resp = requests.post(URL, headers=AUTH_HEADER, json={"number": 315}, timeout=5)
        if resp.status_code != 200:
            return False, f"Status code {resp.status_code}"
        try:
            data = resp.json()
            if sorted(data.get("factors", [])) != EXPECTED_FACTORS:
                return False, f"Incorrect factors: {data}"
            return True, ""
        except ValueError:
            return False, "Invalid JSON"

    num_requests = 50
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        futures = [executor.submit(make_request) for _ in range(num_requests)]
        for future in concurrent.futures.as_completed(futures):
            success, msg = future.result()
            assert success, f"Concurrency test failed: {msg}"


def test_heterogeneous_concurrent_requests():
    rng = random.SystemRandom()
    bases = [1, 2, 3, 16, 81, 121, 9973, 65536, 510510]
    bases.extend(rng.randint(2, 2_000_000) for _ in range(31))
    requests_to_make = [bases[i % len(bases)] for i in range(160)]
    rng.shuffle(requests_to_make)

    with concurrent.futures.ThreadPoolExecutor(max_workers=24) as executor:
        futures = [executor.submit(checked_request, number) for number in requests_to_make]
        for future in concurrent.futures.as_completed(futures):
            future.result()
TEST_EOF

pytest_ok=0
if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    pytest_ok=1
fi

if [ "$race_ok" -eq 1 ] && [ "$pytest_ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
