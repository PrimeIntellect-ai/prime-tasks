#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import math
import random
import requests
import pytest

URL = "http://127.0.0.1:9090/clean"


def compute_expected(data):
    valid_points = [d for d in data if d.get("B") is not None]
    n_valid = len(valid_points)
    mean_a = sum(d["A"] for d in valid_points) / n_valid
    mean_b = sum(d["B"] for d in valid_points) / n_valid

    num = sum((d["A"] - mean_a) * (d["B"] - mean_b) for d in valid_points)
    den = sum((d["A"] - mean_a) ** 2 for d in valid_points)
    beta_1 = num / den
    beta_0 = mean_b - beta_1 * mean_a

    imputed_b = []
    for d in data:
        if d.get("B") is not None:
            imputed_b.append(d["B"])
        else:
            imputed_b.append(beta_0 + beta_1 * d["A"])

    n_total = len(imputed_b)
    mean_b_full = sum(imputed_b) / n_total
    variance = sum((b - mean_b_full) ** 2 for b in imputed_b) / (n_total - 1)
    stddev = math.sqrt(variance)
    se = stddev / math.sqrt(n_total)
    moe = 1.96 * se
    return imputed_b, mean_b_full - moe, mean_b_full + moe


def check_payload(payload):
    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service on 127.0.0.1:9090. Is it running? Error: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    try:
        result = response.json()
    except Exception as e:
        pytest.fail(f"Failed to parse JSON response: {response.text}. Error: {e}")

    expected_b, expected_lower, expected_upper = compute_expected(payload["data"])
    assert "imputed_B" in result, "Response missing 'imputed_B' key"
    assert "ci_lower" in result, "Response missing 'ci_lower' key"
    assert "ci_upper" in result, "Response missing 'ci_upper' key"
    assert isinstance(result["imputed_B"], list), "imputed_B must be an array"
    assert len(result["imputed_B"]) == len(expected_b), "Length of imputed_B does not match expected"

    for act, exp in zip(result["imputed_B"], expected_b):
        assert isinstance(act, (int, float)) and math.isfinite(act), f"Invalid imputed value: {act}"
        assert math.isclose(act, exp, abs_tol=1e-3), f"Imputed value {act} does not match expected {exp}"

    assert isinstance(result["ci_lower"], (int, float)) and math.isfinite(result["ci_lower"])
    assert isinstance(result["ci_upper"], (int, float)) and math.isfinite(result["ci_upper"])
    assert math.isclose(result["ci_lower"], expected_lower, abs_tol=1e-3), f"ci_lower {result['ci_lower']} does not match expected {expected_lower}"
    assert math.isclose(result["ci_upper"], expected_upper, abs_tol=1e-3), f"ci_upper {result['ci_upper']} does not match expected {expected_upper}"


def test_service_payload_1():
    check_payload({
        "data": [
            {"A": 10.0, "B": 15.0},
            {"A": 12.0, "B": 20.0},
            {"A": 15.0, "B": None},
            {"A": 18.0, "B": 35.0},
            {"A": 20.0, "B": None}
        ]
    })


def test_service_payload_2():
    check_payload({
        "data": [
            {"A": 1.0, "B": 2.0},
            {"A": 2.0, "B": None},
            {"A": 3.0, "B": 6.0}
        ]
    })


def test_randomized_regression_and_confidence_intervals():
    rng = random.SystemRandom()
    for _ in range(10):
        n = rng.randint(5, 13)
        xs = rng.sample(range(-80, 121), n)
        intercept = rng.uniform(-30.0, 30.0)
        slope = rng.uniform(-6.0, 6.0)
        if abs(slope) < 0.4:
            slope += 1.25

        rows = []
        for i, x in enumerate(xs):
            noise = rng.uniform(-8.0, 8.0) + 0.015 * x * x
            b = round(intercept + slope * x + noise, 6)
            rows.append({"A": float(x) + rng.uniform(-0.2, 0.2), "B": b})

        missing_count = rng.randint(1, n - 3)
        for index in rng.sample(range(n), missing_count):
            rows[index]["B"] = None
        rng.shuffle(rows)
        check_payload({"data": rows})
TEST_EOF

run_verification() {
    project=/home/user/cleaner_service
    [ -d "$project" ] || return 1
    [ -f "$project/Cargo.toml" ] || return 1
    find "$project" -type f -name '*.rs' -print -quit | grep -q . || return 1

    (cd "$project" && cargo metadata --no-deps --format-version=1 > /tmp/cleaner-metadata.json) || return 1
    (cd "$project" && cargo build --bins --message-format=json-render-diagnostics > /tmp/cleaner-build.json 2>/tmp/cleaner-build.err) || return 1

    python3 - "$project" <<'PY' || return 1
import json, os, sys
project = os.path.realpath(sys.argv[1])
with open('/tmp/cleaner-metadata.json') as f:
    metadata = json.load(f)
packages = [p for p in metadata['packages'] if os.path.realpath(p['manifest_path']) == os.path.join(project, 'Cargo.toml')]
if len(packages) != 1:
    raise SystemExit('Unable to identify the Rust package at the required path')
pkg = packages[0]
preferred = pkg.get('default_run') or pkg['name']
artifacts = []
with open('/tmp/cleaner-build.json') as f:
    for line in f:
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        if item.get('reason') == 'compiler-artifact' and item.get('executable') and 'bin' in item.get('target', {}).get('kind', []):
            artifacts.append(item)
choices = [a for a in artifacts if a['target']['name'] == preferred]
if not choices and len(artifacts) == 1:
    choices = artifacts
if not choices:
    raise SystemExit('Unable to identify the service binary; set package.default-run if the project has multiple binaries')
exe = os.path.realpath(choices[-1]['executable'])
if not os.path.isfile(exe) or not os.access(exe, os.X_OK):
    raise SystemExit('Cargo did not produce an executable Rust service')
with open('/tmp/cleaner-executable', 'w') as f:
    f.write(exe)
PY

    python3 <<'PY' || return 1
import glob, os, signal, time
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        lines = open(table).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        fields = line.split()
        if fields[3] == '0A' and int(fields[1].rsplit(':', 1)[1], 16) == 9090:
            inodes.add(fields[9])
pids = set()
for path in glob.glob('/proc/[0-9]*/fd/*'):
    try:
        target = os.readlink(path)
    except OSError:
        continue
    if target.startswith('socket:[') and target[8:-1] in inodes:
        pids.add(int(path.split('/')[2]))
for pid in pids:
    try: os.kill(pid, signal.SIGTERM)
    except ProcessLookupError: pass
time.sleep(0.5)
for pid in pids:
    try: os.kill(pid, signal.SIGKILL)
    except ProcessLookupError: pass
PY

    exe=$(cat /tmp/cleaner-executable) || return 1
    cd "$project" || return 1
    nohup "$exe" >/tmp/cleaner-service.log 2>&1 &
    service_pid=$!
    cd / || return 1

    ready=0
    for _ in $(seq 1 30); do
        if ! kill -0 "$service_pid" 2>/dev/null; then
            cat /tmp/cleaner-service.log >&2
            return 1
        fi
        if curl -sS --max-time 1 -o /dev/null -X POST -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:9090/clean; then
            ready=1
            break
        fi
        sleep 0.5
    done
    [ "$ready" -eq 1 ] || return 1

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1
}

if run_verification 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
