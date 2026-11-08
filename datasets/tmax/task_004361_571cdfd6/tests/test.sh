#!/bin/bash
mkdir -p /logs/verifier

run_verification() {
    pkill -x nginx 2>/dev/null || true
    pkill -x compute-engine 2>/dev/null || true
    sleep 1

    cd /app/compute-engine || return 1
    cargo build || return 1
    nginx -t -c /app/gateway/nginx.conf || return 1

    bash /app/start.sh >/tmp/app-start.log 2>&1 &
    START_PID=$!

    ready=0
    for _ in $(seq 1 60); do
        if curl -fsS --max-time 1 'http://127.0.0.1:8080/compute?input=1,2' >/dev/null 2>&1; then
            ready=1
            break
        fi
        sleep 1
    done
    [ "$ready" -eq 1 ] || return 1
    kill -0 "$START_PID" 2>/dev/null || return 1
    pgrep -x nginx >/dev/null || return 1

    BACKEND_PID=$(pgrep -x compute-engine | head -n 1)
    [ -n "$BACKEND_PID" ] || return 1
    [ "$(readlink -f "/proc/$BACKEND_PID/exe")" = "/app/compute-engine/target/debug/compute-engine" ] || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import secrets
import requests

GATEWAY_URL = "http://127.0.0.1:8080/compute"
BACKEND_URL = "http://127.0.0.1:9000/compute"


def get_compute(input_str, url=GATEWAY_URL):
    try:
        resp = requests.get(url, params={"input": input_str}, timeout=5)
    except requests.exceptions.RequestException as exc:
        raise AssertionError(f"Failed to connect to {url}: {exc}")

    assert resp.status_code == 200, (
        f"Expected HTTP 200, got {resp.status_code}. Response: {resp.text}"
    )
    try:
        data = resp.json()
    except ValueError:
        raise AssertionError(f"Response is not valid JSON: {resp.text}")

    assert isinstance(data, dict), f"Expected a JSON object, got: {data!r}"
    assert set(data.keys()) == {"mean", "variance"}, (
        f"Response must contain strictly the keys mean and variance: {data}"
    )
    for key in ("mean", "variance"):
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool), (
            f"{key} must be numeric, got {data[key]!r}"
        )
        assert math.isfinite(data[key]), f"{key} must be finite, got {data[key]!r}"
    return data


def expected_stats(values):
    mean = math.fsum(values) / len(values)
    if len(values) < 2:
        return mean, 0.0
    variance = math.fsum((x - mean) ** 2 for x in values) / len(values)
    return mean, variance


def assert_stats(data, values):
    expected_mean, expected_variance = expected_stats(values)
    mean_tol = max(1e-10, 8 * math.ulp(expected_mean))
    variance_tol = max(1e-9, abs(expected_variance) * 1e-10)
    assert math.isclose(data["mean"], expected_mean, rel_tol=0.0, abs_tol=mean_tol), (
        f"Expected mean {expected_mean}, got {data['mean']}"
    )
    assert math.isclose(
        data["variance"], expected_variance, rel_tol=0.0, abs_tol=variance_tol
    ), f"Expected population variance {expected_variance}, got {data['variance']}"


def test_numerical_stability_fixed_case():
    values = [100000000.0, 100000001.0, 100000002.0]
    data = get_compute("100000000.0,100000001.0,100000002.0")
    assert_stats(data, values)


def test_format_parsing_edge_cases_fixed_case():
    data = get_compute("10.0,NaN,invalid,N/A,20.0")
    assert math.isclose(data["mean"], 15.0, rel_tol=1e-5)
    assert math.isclose(data["variance"], 25.0, rel_tol=1e-5)


def test_single_valid_value_fixed_case():
    data = get_compute("42.0,NaN")
    assert math.isclose(data["mean"], 42.0, rel_tol=1e-5)
    assert math.isclose(data["variance"], 0.0, rel_tol=1e-5)


def test_randomized_derived_inputs_and_invalid_filtering():
    rng = secrets.SystemRandom()
    invalid = ["NaN", "infinity", "-infinity", "inf", "N/A", "invalid", ""]

    for _ in range(10):
        baseline = rng.randint(10**10, 10**12)
        offsets = [rng.randint(-2000, 2000) for _ in range(rng.randint(3, 12))]
        values = [float(baseline + offset) for offset in offsets]
        tokens = [format(value, ".17g") for value in values]
        for bad in rng.sample(invalid, rng.randint(2, 5)):
            tokens.insert(rng.randrange(len(tokens) + 1), bad)
        data = get_compute(",".join(tokens))
        assert_stats(data, values)


def test_random_single_value_and_proxy_integration():
    value = float(secrets.SystemRandom().randint(-10**9, 10**9))
    query = f"NaN,N/A,{value:.17g},infinity"
    gateway = get_compute(query, GATEWAY_URL)
    backend = get_compute(query, BACKEND_URL)
    assert_stats(gateway, [value])
    assert gateway == backend, (
        f"Gateway response {gateway} differs from backend response {backend}"
    )
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1
}

if run_verification; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
