#!/bin/bash
mkdir -p /logs/verifier

# Stop anything the agent left listening on 8080 so the verifier exercises a
# freshly compiled copy of analyzer.c rather than an unrelated prestarted server.
python3 - <<'PY'
import os, signal
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) > 9 and fields[1].split(':')[-1].upper() == '1F90' and fields[3] == '0A':
                    inodes.add(fields[9])
    except OSError:
        pass
for pid in filter(str.isdigit, os.listdir('/proc')):
    fd_dir = f'/proc/{pid}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                try:
                    os.kill(int(pid), signal.SIGTERM)
                except (ProcessLookupError, PermissionError):
                    pass
                break
    except OSError:
        pass
PY
sleep 1

if ! gcc -std=gnu17 -O2 /home/user/analyzer.c -o /tmp/analyzer_under_test -lm -pthread >/tmp/analyzer_build.log 2>&1; then
    cat /tmp/analyzer_build.log
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cd /home/user || true
/tmp/analyzer_under_test >/tmp/analyzer_server.log 2>&1 &
SERVER_PID=$!
cleanup() {
    kill "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import math
import os
import re
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
AUTH_HEADER = {"Authorization": "Bearer RES-994"}
BINARY = "/tmp/analyzer_under_test"


def _listener_pids(port):
    inodes = set()
    port_hex = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if (len(fields) > 9 and fields[1].split(":")[-1].upper() == port_hex
                            and fields[3] == "0A"):
                        inodes.add(fields[9])
        except OSError:
            pass

    owners = set()
    for pid in filter(str.isdigit, os.listdir("/proc")):
        try:
            for fd in os.listdir(f"/proc/{pid}/fd"):
                try:
                    target = os.readlink(f"/proc/{pid}/fd/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(pid))
        except OSError:
            pass
    return owners


def _wait_for_server():
    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        try:
            requests.get(f"{BASE_URL}/stats", timeout=0.5)
            return
        except requests.RequestException as exc:
            last_error = exc
            time.sleep(0.1)
    pytest.fail(f"Freshly compiled analyzer did not start its HTTP server: {last_error}")


@pytest.fixture(scope="session", autouse=True)
def require_compiled_c_server():
    _wait_for_server()
    owners = _listener_pids(8080)
    assert owners, "No process owns the listening socket on port 8080"
    matching = []
    for pid in owners:
        try:
            if os.path.samefile(f"/proc/{pid}/exe", BINARY):
                matching.append(pid)
        except OSError:
            pass
    assert matching, (
        "Port 8080 is not served by the freshly compiled /home/user/analyzer.c; "
        f"listener PIDs were {sorted(owners)}"
    )


def test_c_source_contains_required_implementation():
    path = "/home/user/analyzer.c"
    assert os.path.isfile(path), "Missing required /home/user/analyzer.c"
    assert not os.path.islink(path), "analyzer.c must be a real C source file"
    source = open(path, encoding="utf-8", errors="replace").read()
    assert source.strip(), "analyzer.c is empty"

    # Ignore comments when looking for executable implementation elements.
    code = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    code = re.sub(r"//[^\n]*", "", code)
    lower = code.lower()

    assert re.search(r"\bmain\s*\(", code), "analyzer.c has no main function"
    for call in ("socket", "bind", "listen", "accept"):
        assert re.search(rf"\b{call}\s*\(", lower), (
            f"HTTP server does not appear to be implemented in C: missing {call}()"
        )

    assert re.search(r"\b(fopen|open)\s*\(", lower), (
        "analyzer.c does not appear to read an extracted dataset"
    )
    assert re.search(r"\b(strtod|strtof|sscanf|fscanf)\s*\(", lower), (
        "analyzer.c lacks numeric parsing needed to reject malformed observations"
    )
    assert "slope" in lower, "analyzer.c does not contain a slope calculation/result"
    assert "bootstrap" in lower, "analyzer.c does not contain a bootstrap implementation"
    assert re.search(r"\b(for|while)\s*\(", lower), "No sampling/analysis loop found in analyzer.c"
    numeric_literals = [int(x) for x in re.findall(r"(?<![A-Za-z0-9_])([0-9]+)(?![A-Za-z0-9_])", code)]
    assert any(n >= 1000 for n in numeric_literals), (
        "analyzer.c does not specify the required minimum of 1,000 bootstrap resamples"
    )
    assert (re.search(r"\b(rand|random|drand48)\s*\(", lower)
            or any(token in lower for token in ("rng", "random_seed", "lcg"))), (
        "analyzer.c lacks a random/resampling mechanism for bootstrap sampling"
    )


def test_unauthorized_access():
    """Test that requests without the correct authorization header are rejected."""
    try:
        response = requests.get(f"{BASE_URL}/stats", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}/stats: {e}")

    assert response.status_code == 401, f"Expected HTTP 401 Unauthorized without auth header, got {response.status_code}"


def test_incorrect_authorization_is_rejected():
    for endpoint in ("/stats", "/data"):
        response = requests.get(
            f"{BASE_URL}{endpoint}",
            headers={"Authorization": "Bearer WRONG"},
            timeout=5,
        )
        assert response.status_code == 401, f"Expected HTTP 401 for incorrect token on {endpoint}"


def _exact_bootstrap_percentile_interval(points):
    """Derive the percentile CI independently from all n^n bootstrap samples."""
    n = len(points)
    slopes = []
    for sample_indexes in itertools.product(range(n), repeat=n):
        xs = [points[i][0] for i in sample_indexes]
        ys = [points[i][1] for i in sample_indexes]
        xbar = sum(xs) / n
        ybar = sum(ys) / n
        denominator = sum((x - xbar) ** 2 for x in xs)
        if denominator == 0:
            continue
        numerator = sum((x - xbar) * (y - ybar) for x, y in zip(xs, ys))
        slopes.append(numerator / denominator)
    slopes.sort()

    def percentile(p):
        position = p * (len(slopes) - 1)
        lo = int(math.floor(position))
        hi = int(math.ceil(position))
        if lo == hi:
            return slopes[lo]
        fraction = position - lo
        return slopes[lo] * (1 - fraction) + slopes[hi] * fraction

    return percentile(0.025), percentile(0.975)


def test_stats_endpoint():
    """Test the /stats endpoint returns correct statistical results."""
    try:
        response = requests.get(f"{BASE_URL}/stats", headers=AUTH_HEADER, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}/stats: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK from /stats, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from /stats is not valid JSON. Response text: {response.text}")

    assert "slope" in data, "Missing 'slope' key in /stats response"
    assert "bootstrap_ci_lower" in data, "Missing 'bootstrap_ci_lower' key in /stats response"
    assert "bootstrap_ci_upper" in data, "Missing 'bootstrap_ci_upper' key in /stats response"

    try:
        slope = float(data["slope"])
    except (ValueError, TypeError):
        pytest.fail(f"Slope value '{data['slope']}' cannot be converted to float.")

    assert math.isclose(slope, 2.0114, abs_tol=0.01), f"Reported slope {slope} is not within 0.01 tolerance of 2.0114"

    try:
        lower = float(data["bootstrap_ci_lower"])
        upper = float(data["bootstrap_ci_upper"])
    except (ValueError, TypeError):
        pytest.fail("Bootstrap confidence interval values must be numeric")

    assert math.isfinite(lower) and math.isfinite(upper), "Bootstrap CI values must be finite"
    assert lower < slope < upper, f"Bootstrap CI [{lower}, {upper}] must contain slope {slope}"
    assert upper - lower > 0.005, "Bootstrap CI is implausibly degenerate"

    points = [(1.0, 2.1), (2.0, 3.9), (3.0, 6.2), (4.0, 8.0), (5.0, 9.9), (6.0, 12.1)]
    expected_lower, expected_upper = _exact_bootstrap_percentile_interval(points)
    # Allow Monte Carlo variation from implementations using the required 1,000+
    # random resamples while still rejecting arbitrary or placeholder values.
    assert abs(lower - expected_lower) <= 0.12, (
        f"Bootstrap lower bound {lower} is inconsistent with resampling the dataset "
        f"(independent percentile result {expected_lower})"
    )
    assert abs(upper - expected_upper) <= 0.12, (
        f"Bootstrap upper bound {upper} is inconsistent with resampling the dataset "
        f"(independent percentile result {expected_upper})"
    )


def test_data_endpoint():
    """Test the /data endpoint returns the correct cleaned dataset."""
    try:
        response = requests.get(f"{BASE_URL}/data", headers=AUTH_HEADER, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}/data: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK from /data, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from /data is not valid JSON. Response text: {response.text}")

    assert isinstance(data, list), f"Response from /data should be a JSON array, got {type(data).__name__}"

    expected_data = [
        {"alpha": 1.0, "beta": 2.1},
        {"alpha": 2.0, "beta": 3.9},
        {"alpha": 3.0, "beta": 6.2},
        {"alpha": 4.0, "beta": 8.0},
        {"alpha": 5.0, "beta": 9.9},
        {"alpha": 6.0, "beta": 12.1}
    ]

    assert len(data) == 6, f"Expected 6 valid data points, got {len(data)}. Ensure invalid observations are dropped."

    for expected in expected_data:
        found = False
        for item in data:
            if "alpha" in item and "beta" in item:
                try:
                    alpha_val = float(item["alpha"])
                    beta_val = float(item["beta"])
                    if math.isclose(alpha_val, expected["alpha"], abs_tol=0.001) and \
                       math.isclose(beta_val, expected["beta"], abs_tol=0.001):
                        found = True
                        break
                except (ValueError, TypeError):
                    continue
        assert found, f"Expected data point {expected} not found in /data response"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    cat /tmp/analyzer_build.log 2>/dev/null || true
    cat /tmp/analyzer_server.log 2>/dev/null || true
    echo "0" > /logs/verifier/reward.txt
fi
