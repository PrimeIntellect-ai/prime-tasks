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

# Interpose a recorder in front of the supplied binary. This verifies that the
# running service invokes it for each generated sample. The optional shift mode
# also lets the tests verify that validation uses the generated spectrum rather
# than merely echoing the requested center.
rm -f /tmp/spectra_gen_calls /tmp/spectra_gen_shift
: > /tmp/spectra_gen_calls
chmod 666 /tmp/spectra_gen_calls
mv /app/spectra_gen /app/spectra_gen.verifier-real
cat << 'WRAPPER_EOF' > /app/spectra_gen
#!/bin/bash
printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> /tmp/spectra_gen_calls
if [ -f /tmp/spectra_gen_shift ]; then
    shifted_mu=$(python3 -c 'import sys; print(float(sys.argv[1]) + 8.0)' "$2")
    exec /app/spectra_gen.verifier-real "$1" "$shifted_mu" "$3"
fi
exec /app/spectra_gen.verifier-real "$@"
WRAPPER_EOF
chmod 755 /app/spectra_gen

cleanup() {
    rm -f /tmp/spectra_gen_shift
    if [ -e /app/spectra_gen.verifier-real ]; then
        rm -f /app/spectra_gen
        mv /app/spectra_gen.verifier-real /app/spectra_gen
    fi
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import statistics
import subprocess

import requests
import pytest

BASE_URL = "http://127.0.0.1:8080/generate"
AUTH_HEADER = {"Authorization": "Bearer ML-DATA-TOKEN"}
REAL_BINARY = "/app/spectra_gen.verifier-real"
CALL_LOG = "/tmp/spectra_gen_calls"


def post(payload, headers=AUTH_HEADER):
    return requests.post(BASE_URL, json=payload, headers=headers, timeout=8)


def binary_spectrum(a, mu, sigma):
    output = subprocess.check_output(
        [REAL_BINARY, str(a), str(mu), str(sigma)], text=True, timeout=5
    )
    values = [float(v) for v in output.split()]
    assert len(values) == 100
    return values


def recorded_calls():
    calls = []
    with open(CALL_LOG, encoding="utf-8") as f:
        for line in f:
            fields = line.rstrip("\n").split("\t")
            if len(fields) == 3:
                calls.append(tuple(float(v) for v in fields))
    return calls


def test_missing_auth():
    payload = {"a": 10.0, "mu": 50.0, "sigma": 5.0, "noise_level": 0.0, "baseline_slope": 0.1}
    try:
        resp = requests.post(BASE_URL, json=payload, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the API on 127.0.0.1:8080. Is the server running?")

    assert resp.status_code == 401, f"Expected 401 Unauthorized when missing auth, got {resp.status_code}. Body: {resp.text}"


def test_invalid_auth():
    payload = {"a": 10.0, "mu": 50.0, "sigma": 5.0, "noise_level": 0.0, "baseline_slope": 0.1}
    headers = {"Authorization": "Bearer INVALID-TOKEN"}
    resp = requests.post(BASE_URL, json=payload, headers=headers, timeout=5)

    assert resp.status_code == 401, f"Expected 401 Unauthorized with invalid auth, got {resp.status_code}. Body: {resp.text}"


def test_successful_generation_and_augmentation():
    payload = {"a": 10.0, "mu": 50.0, "sigma": 5.0, "noise_level": 0.0, "baseline_slope": 0.1}
    resp = post(payload)

    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Body: {resp.text}"

    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Body: {resp.text}")

    assert "spectrum" in data, "Response JSON missing 'spectrum' key."
    assert "fitted_mu" in data, "Response JSON missing 'fitted_mu' key."

    spectrum = data["spectrum"]
    assert isinstance(spectrum, list), "'spectrum' should be a list."
    assert len(spectrum) == 100, f"Expected 100 points in spectrum, got {len(spectrum)}."

    for i in range(100):
        base_val = 10.0 * math.exp(-((i - 50.0) ** 2) / (2 * 5.0 ** 2))
        expected_val = base_val + (i * 0.1)
        assert abs(spectrum[i] - expected_val) < 1e-4, \
            f"Spectrum mismatch at index {i}. Expected ~{expected_val}, got {spectrum[i]}."

    fitted_mu = data["fitted_mu"]
    assert isinstance(fitted_mu, (float, int)), "'fitted_mu' should be a number."
    assert abs(fitted_mu - 50.0) < 1e-2, f"Expected fitted_mu to be very close to 50.0, got {fitted_mu}."


def test_randomized_parameters_use_binary_and_apply_baseline():
    rng = secrets.SystemRandom()
    cases = []
    for _ in range(3):
        cases.append({
            "a": round(rng.uniform(6.0, 20.0), 6),
            "mu": round(rng.uniform(25.0, 75.0), 6),
            "sigma": round(rng.uniform(3.0, 9.0), 6),
            "noise_level": 0.0,
            "baseline_slope": round(rng.uniform(-0.12, 0.16), 6),
        })

    before = len(recorded_calls())
    for payload in cases:
        base = binary_spectrum(payload["a"], payload["mu"], payload["sigma"])
        resp = post(payload)
        assert resp.status_code == 200, f"Random valid payload failed: {payload}; body: {resp.text}"
        data = resp.json()
        assert set(("spectrum", "fitted_mu")).issubset(data)
        assert isinstance(data["spectrum"], list) and len(data["spectrum"]) == 100
        for i, value in enumerate(data["spectrum"]):
            expected = base[i] + i * payload["baseline_slope"]
            assert isinstance(value, (int, float))
            assert math.isfinite(value)
            assert abs(value - expected) < 1e-5, \
                f"Incorrect binary output/baseline for payload {payload} at index {i}"
        assert isinstance(data["fitted_mu"], (int, float))
        assert abs(data["fitted_mu"] - payload["mu"]) < 1e-2

    new_calls = recorded_calls()[before:]
    assert len(new_calls) >= len(cases), "The service did not execute /app/spectra_gen for every request"
    for payload in cases:
        wanted = (payload["a"], payload["mu"], payload["sigma"])
        assert any(all(abs(x - y) < 1e-9 for x, y in zip(call, wanted)) for call in new_calls), \
            f"No binary invocation recorded with requested arguments {wanted}"


def test_nonzero_noise_is_added_to_binary_output():
    payload = {"a": 18.0, "mu": 43.25, "sigma": 6.0, "noise_level": 0.3, "baseline_slope": -0.025}
    base = binary_spectrum(payload["a"], payload["mu"], payload["sigma"])
    responses = [post(payload), post(payload)]
    spectra = []
    for resp in responses:
        assert resp.status_code == 200, f"Moderate-noise valid sample failed: {resp.text}"
        data = resp.json()
        spectrum = data["spectrum"]
        assert isinstance(spectrum, list) and len(spectrum) == 100
        residuals = [spectrum[i] - base[i] - i * payload["baseline_slope"] for i in range(100)]
        assert 0.15 < statistics.pstdev(residuals) < 0.50, "Noise does not have the requested scale"
        assert abs(statistics.mean(residuals)) < 0.15, "Noise is not approximately zero-mean"
        assert abs(data["fitted_mu"] - payload["mu"]) <= 2.0
        spectra.append(spectrum)
    assert spectra[0] != spectra[1], "Repeated requests returned identical noise"


def test_validation_uses_fitted_generated_spectrum():
    payload = {"a": 20.0, "mu": 41.0, "sigma": 4.0, "noise_level": 0.0, "baseline_slope": 0.03}
    with open("/tmp/spectra_gen_shift", "w", encoding="utf-8") as f:
        f.write("8\n")
    try:
        resp = post(payload)
    finally:
        os.unlink("/tmp/spectra_gen_shift")

    assert resp.status_code == 400, \
        f"Expected validation to reject a generated peak shifted from requested mu; got {resp.status_code}: {resp.text}"
    assert resp.json().get("error") == "Validation failed"
    assert any(
        abs(a - payload["a"]) < 1e-9 and abs(mu - payload["mu"]) < 1e-9 and abs(sigma - payload["sigma"]) < 1e-9
        for a, mu, sigma in recorded_calls()
    ), "Shift-validation request was not passed to /app/spectra_gen with the requested arguments"


def test_validation_failure_due_to_high_noise():
    payload = {"a": 1.0, "mu": 50.0, "sigma": 5.0, "noise_level": 10000.0, "baseline_slope": 0.1}
    resp = post(payload)

    assert resp.status_code == 400, f"Expected 400 Bad Request for validation failure, got {resp.status_code}. Body: {resp.text}"

    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Body: {resp.text}")

    assert data.get("error") == "Validation failed", f"Expected error message 'Validation failed', got: {data.get('error')}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
