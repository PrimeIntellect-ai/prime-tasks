#!/bin/bash
set -e
mkdir -p /logs/verifier

# Interpose gcc during service startup so compilation of mc_sim.c and execution
# of the resulting native program can be observed without prescribing its CLI.
rm -rf /tmp/verifier-bin
mkdir -p /tmp/verifier-bin
rm -f /tmp/verifier_mc_compiles /tmp/verifier_mc_invocations
cat > /tmp/verifier-bin/gcc <<'GCC_EOF'
#!/bin/bash
set -e
args=("$@")
/usr/bin/gcc "${args[@]}"
status=$?
[ "$status" -eq 0 ] || exit "$status"

is_mc=0
out="a.out"
for ((i=0; i<${#args[@]}; i++)); do
    case "${args[$i]}" in
        *mc_sim.c) is_mc=1 ;;
        -o)
            if (( i + 1 < ${#args[@]} )); then
                out="${args[$((i+1))]}"
            fi
            ;;
    esac
done

if [ "$is_mc" -eq 1 ]; then
    printf '%s\n' "$PWD/$out" >> /tmp/verifier_mc_compiles
    if [[ "$out" != /* ]]; then
        out="$PWD/$out"
    fi
    if [ -f "$out" ] && [ -x "$out" ]; then
        real="${out}.verifier-real"
        rm -f "$real"
        mv "$out" "$real"
        {
            echo '#!/bin/bash'
            echo 'printf "%s\\n" "invoked" >> /tmp/verifier_mc_invocations'
            printf 'exec %q "$@"\n' "$real"
        } > "$out"
        chmod +x "$out"
    fi
fi
exit 0
GCC_EOF
chmod +x /tmp/verifier-bin/gcc

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import time
import requests
import pytest
import math

SERVICE_URL = "http://127.0.0.1:8080"
AUTH_HEADER = {"Authorization": "Bearer sim-perf-token-2024"}


def log_lines(path):
    if not os.path.isfile(path):
        return []
    with open(path, "r", errors="replace") as f:
        return [line for line in f if line.strip()]


@pytest.fixture(scope="module", autouse=True)
def start_service():
    """Start the service and yield, then kill it."""
    script_path = "/home/user/start_service.sh"
    assert os.path.isfile(script_path), f"Startup script not found: {script_path}"
    assert os.access(script_path, os.X_OK), f"Startup script is not executable: {script_path}"

    env = os.environ.copy()
    env["PATH"] = "/tmp/verifier-bin:" + env.get("PATH", "")
    proc = subprocess.Popen(["/bin/bash", script_path], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, env=env)

    service_up = False
    for _ in range(30):
        try:
            requests.get(SERVICE_URL, timeout=0.5)
            service_up = True
            break
        except requests.exceptions.ConnectionError:
            time.sleep(0.5)

    if not service_up:
        proc.terminate()
        pytest.fail("Service did not start on 127.0.0.1:8080 within 15 seconds.")

    yield

    proc.terminate()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()


def find_valid_mc_source():
    candidates = []
    for root in ("/home/user", "/app"):
        for directory, _, files in os.walk(root):
            if "mc_sim.c" in files:
                candidates.append(os.path.join(directory, "mc_sim.c"))

    assert candidates, "mc_sim.c was not created under /home/user or /app"
    failures = []
    for path in candidates:
        text = open(path, "r", errors="replace").read()
        # Ignore comments so parameter names or values merely mentioned in a
        # comment do not satisfy the artifact check.
        code = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
        code = re.sub(r"//[^\n]*", "", code)
        checks = {
            "seed offset 42042": re.search(r"(?<![A-Za-z0-9_])42042(?![A-Za-z0-9_])", code),
            "drift 0.05": re.search(r"(?<![A-Za-z0-9_.])(?:0?\.050*|5(?:\.0*)?[eE]-0?2)(?![A-Za-z0-9_.])", code),
            "volatility 0.20": re.search(r"(?<![A-Za-z0-9_.])(?:0?\.20*|2(?:\.0*)?[eE]-0?1)(?![A-Za-z0-9_.])", code),
            "100000 paths": re.search(r"(?<![A-Za-z0-9_])100000(?![A-Za-z0-9_])", code),
            "an iteration construct": re.search(r"\b(?:for|while)\s*\(", code),
            "seeded/random path generation": re.search(r"\b(?:seed|rand|random|rng|xorshift|splitmix|pcg)[A-Za-z0-9_]*\b", code, re.I),
        }
        missing = [name for name, match in checks.items() if not match]
        if not missing:
            return path
        failures.append(f"{path}: missing {', '.join(missing)}")
    pytest.fail("No mc_sim.c contains the required extracted parameters and simulation structure: " + "; ".join(failures))


def get_simulation(start_price):
    resp = requests.get(f"{SERVICE_URL}/simulate", params={"start_price": start_price},
                        headers=AUTH_HEADER, timeout=5)
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Body: {resp.text}"
    try:
        value = float(resp.text.strip())
    except ValueError:
        pytest.fail(f"Could not parse response as float: {resp.text}")
    assert math.isfinite(value), f"Simulation returned a non-finite value: {resp.text}"
    return value


def test_c_artifact_and_startup_compilation():
    find_valid_mc_source()
    compiled = log_lines("/tmp/verifier_mc_compiles")
    assert compiled, "start_service.sh did not compile mc_sim.c with gcc"


def test_auth_required():
    """Test that endpoints require the correct Bearer token."""
    resp = requests.get(f"{SERVICE_URL}/simulate?start_price=100")
    assert resp.status_code in [401, 403], f"Expected 401/403 without auth, got {resp.status_code}"

    resp = requests.get(f"{SERVICE_URL}/regression")
    assert resp.status_code in [401, 403], f"Expected 401/403 without auth, got {resp.status_code}"

    bad = {"Authorization": "Bearer wrong-token"}
    assert requests.get(f"{SERVICE_URL}/simulate?start_price=100", headers=bad).status_code in [401, 403]
    assert requests.get(f"{SERVICE_URL}/regression", headers=bad).status_code in [401, 403]


def test_simulate_endpoint_deterministic():
    """Test that the simulate endpoint returns deterministic results."""
    results = set()
    for _ in range(5):
        resp = requests.get(f"{SERVICE_URL}/simulate?start_price=100", headers=AUTH_HEADER)
        assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Body: {resp.text}"
        try:
            val = float(resp.text.strip())
            assert math.isfinite(val)
            results.add(val)
        except ValueError:
            pytest.fail(f"Could not parse response as float: {resp.text}")

    assert len(results) == 1, f"Simulation is not deterministic, got multiple results for start_price=100: {results}"


def test_simulation_uses_start_price_and_parameters():
    # Exercise prices not used by the requested regression so a table of the ten
    # regression answers is insufficient. A deterministic GBM Monte Carlo mean
    # with drift 0.05 should have a return close to exp(0.05).
    starts = [73.25, 100.0, 145.5, 247.75]
    first = [get_simulation(x) for x in starts]
    second = [get_simulation(x) for x in starts]
    assert first == second, "Simulation is not exactly reproducible for arbitrary starting prices"
    assert len(set(first)) == len(first), "Simulation ignored start_price or returned a constant"

    returns = [y / x for x, y in zip(starts, first)]
    assert all(1.01 < r < 1.10 for r in returns), (
        f"Results are inconsistent with the extracted drift 0.05: returns={returns}")
    assert max(returns) - min(returns) < 1e-5, (
        f"Fixed-seed path reduction should scale consistently with start_price: {returns}")


def test_regression_endpoint():
    """Test the regression endpoint and verify it matches the simulation results."""
    prices = []
    for x in range(100, 200, 10):
        resp = requests.get(f"{SERVICE_URL}/simulate?start_price={x}", headers=AUTH_HEADER)
        assert resp.status_code == 200
        y = float(resp.text.strip())
        assert math.isfinite(y)
        prices.append((x, y))

    n = len(prices)
    sum_x = sum(x for x, y in prices)
    sum_y = sum(y for x, y in prices)
    sum_xy = sum(x * y for x, y in prices)
    sum_x2 = sum(x * x for x, y in prices)

    denominator = (n * sum_x2 - sum_x ** 2)
    expected_m = (n * sum_xy - sum_x * sum_y) / denominator
    expected_c = (sum_y - expected_m * sum_x) / n

    assert 1.01 < expected_m < 1.10, f"Regression slope is inconsistent with drift 0.05: {expected_m}"
    assert abs(expected_c) < 1.0, f"Unexpected non-proportional simulation intercept: {expected_c}"

    resp = requests.get(f"{SERVICE_URL}/regression", headers=AUTH_HEADER)
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Body: {resp.text}"

    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Could not parse response as JSON: {resp.text}")

    assert "slope" in data, "Missing 'slope' in regression response"
    assert "intercept" in data, "Missing 'intercept' in regression response"

    actual_m = float(data["slope"])
    actual_c = float(data["intercept"])
    assert math.isfinite(actual_m) and math.isfinite(actual_c)

    assert math.isclose(actual_m, expected_m, rel_tol=1e-3), f"Slope mismatch: expected {expected_m}, got {actual_m}"
    assert math.isclose(actual_c, expected_c, rel_tol=1e-3), f"Intercept mismatch: expected {expected_c}, got {actual_c}"


def test_native_c_program_was_executed():
    assert log_lines("/tmp/verifier_mc_invocations"), (
        "The executable compiled from mc_sim.c was never run; the service must execute the C core logic")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
