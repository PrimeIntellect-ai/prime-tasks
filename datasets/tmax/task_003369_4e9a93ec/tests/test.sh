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
echo "0" > /logs/verifier/reward.txt

REAL_ORACLE=/app/.spectra_oracle_verifier_real
CALL_LOG=/tmp/spectra_oracle_calls.log

cleanup() {
    rm -f /app/spectra_oracle
    if [ -e "$REAL_ORACLE" ]; then
        mv -f "$REAL_ORACLE" /app/spectra_oracle
        chmod 755 /app/spectra_oracle
    fi
}
trap cleanup EXIT

mv /app/spectra_oracle "$REAL_ORACLE"
chmod 755 "$REAL_ORACLE"
: > "$CALL_LOG"
chmod 666 "$CALL_LOG"
cat > /app/spectra_oracle <<'WRAPPER_EOF'
#!/bin/sh
printf '%s\n' "$*" >> /tmp/spectra_oracle_calls.log
exec /app/.spectra_oracle_verifier_real "$@"
WRAPPER_EOF
chmod 755 /app/spectra_oracle

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import secrets
import subprocess
import time

import pytest
import requests

ORACLE = "/app/.spectra_oracle_verifier_real"
CALL_LOG = "/tmp/spectra_oracle_calls.log"


def generate_spectrum(x, y, z):
    proc = subprocess.run(
        [ORACLE, str(x), str(y), str(z)],
        check=True,
        text=True,
        capture_output=True,
        timeout=5,
    )
    parts = proc.stdout.strip().split(",")
    assert len(parts) == 10, f"Oracle returned an invalid spectrum: {proc.stdout!r}"
    spectrum = [float(v) for v in parts]
    assert all(math.isfinite(v) for v in spectrum), "Oracle returned non-finite values"
    return spectrum


def oracle_call_count():
    try:
        with open(CALL_LOG, "r", encoding="utf-8") as f:
            return sum(1 for _ in f)
    except FileNotFoundError:
        return 0


def check_optimization(target_x, target_y, target_z):
    spectrum = generate_spectrum(target_x, target_y, target_z)
    payload = ",".join(f"{v:.6f}" for v in spectrum)
    calls_before = oracle_call_count()

    url = "http://127.0.0.1:8080/optimize"
    try:
        response = requests.post(url, data=payload, timeout=10)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to or read from the optimization service at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"

    text = response.text.strip()
    parts = text.split(",")
    assert len(parts) == 3, f"Expected 3 comma-separated values (x,y,z), got: {text}"

    try:
        res_x, res_y, res_z = map(float, parts)
    except ValueError:
        pytest.fail(f"Failed to parse response as 3 floats: {text}")

    assert all(math.isfinite(v) for v in (res_x, res_y, res_z)), f"Response contains non-finite values: {text}"

    dist = math.sqrt((res_x - target_x)**2 + (res_y - target_y)**2 + (res_z - target_z)**2)
    assert dist <= 0.2, f"Returned parameters ({res_x}, {res_y}, {res_z}) are too far from target ({target_x}, {target_y}, {target_z}). Distance: {dist}"

    # The requested optimization must actually consult /app/spectra_oracle.
    for _ in range(20):
        if oracle_call_count() > calls_before:
            break
        time.sleep(0.01)
    assert oracle_call_count() > calls_before, "The service did not invoke /app/spectra_oracle for this optimization request"


def random_case():
    rng = secrets.SystemRandom()
    # x is chosen from a non-periodically-ambiguous portion of the allowed domain.
    return (
        rng.uniform(3.9, 6.1),
        rng.uniform(0.5, 9.5),
        rng.uniform(0.5, 9.5),
    )


CASES = [random_case() for _ in range(3)]


@pytest.mark.parametrize("target_x,target_y,target_z", CASES)
def test_optimization(target_x, target_y, target_z):
    check_optimization(target_x, target_y, target_z)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
