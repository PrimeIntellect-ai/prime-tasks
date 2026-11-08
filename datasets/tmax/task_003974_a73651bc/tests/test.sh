#!/bin/bash
set +e
mkdir -p /logs/verifier
reward=0
service_pid=""

cleanup() {
    if [ -n "$service_pid" ]; then
        kill "$service_pid" 2>/dev/null || true
        wait "$service_pid" 2>/dev/null || true
    fi
    rm -f /app/gonomaly-1.0.0/verifier_sort_test.go /tmp/pipeline_verifier_bin
}
trap cleanup EXIT

run_verification() {
    test -f /home/user/pipeline/main.go || return 1
    test -f /home/user/pipeline/go.mod || return 1

    # Confirm that the submitted application imports and calls the requested library.
    grep -q 'github.com/ds-tools/gonomaly' /home/user/pipeline/main.go /home/user/pipeline/go.mod || return 1
    grep -Eq 'CleanDataset[[:space:]]*\(' /home/user/pipeline/main.go || return 1
    (
        cd /home/user/pipeline &&
        go list -deps . | grep -Fxq 'github.com/ds-tools/gonomaly' &&
        go build -o /tmp/pipeline_verifier_bin .
    ) || return 1

    # Exercise SortEigenvalues directly on runtime-generated values and verify
    # descending ordering, index preservation, and selection of the maximum first.
    cat > /app/gonomaly-1.0.0/verifier_sort_test.go <<'GO_EOF'
package gonomaly

import (
    "crypto/rand"
    "encoding/binary"
    "testing"
)

func TestVerifierSortEigenvaluesDescending(t *testing.T) {
    values := make([]float64, 37)
    for i := range values {
        var b [4]byte
        if _, err := rand.Read(b[:]); err != nil {
            t.Fatal(err)
        }
        values[i] = float64(int64(binary.LittleEndian.Uint32(b[:]))-2147483648) + float64(i)/1000
    }

    got := SortEigenvalues(values)
    if len(got) != len(values) {
        t.Fatalf("length changed: got %d, want %d", len(got), len(values))
    }

    seen := make([]bool, len(values))
    max := values[0]
    for _, v := range values[1:] {
        if v > max {
            max = v
        }
    }
    for i, e := range got {
        if e.Index < 0 || e.Index >= len(values) || seen[e.Index] {
            t.Fatalf("invalid or duplicate source index: %d", e.Index)
        }
        seen[e.Index] = true
        if e.Value != values[e.Index] {
            t.Fatalf("value/index mismatch at output %d", i)
        }
        if i > 0 && got[i-1].Value < e.Value {
            t.Fatalf("not descending at output %d: %v before %v", i, got[i-1].Value, e.Value)
        }
    }
    if got[0].Value != max {
        t.Fatalf("first component is %v, maximum is %v", got[0].Value, max)
    }
}
GO_EOF
    (cd /app/gonomaly-1.0.0 && go test -run '^TestVerifierSortEigenvaluesDescending$') || return 1
    rm -f /app/gonomaly-1.0.0/verifier_sort_test.go

    # Stop any previously submitted process and execute the freshly compiled artifact.
    python3 - <<'PY_EOF' || return 1
import glob
import os
import signal
import time

ports = {8080, 8081}
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        lines = open(table).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        fields = line.split()
        if len(fields) > 9 and fields[3] == '0A':
            port = int(fields[1].rsplit(':', 1)[1], 16)
            if port in ports:
                inodes.add(fields[9])

pids = set()
for fd in glob.glob('/proc/[0-9]*/fd/*'):
    try:
        target = os.readlink(fd)
    except OSError:
        continue
    if target.startswith('socket:[') and target[8:-1] in inodes:
        pids.add(int(fd.split('/')[2]))

for pid in pids:
    if pid not in (1, os.getpid(), os.getppid()):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
time.sleep(0.3)
for pid in pids:
    if pid not in (1, os.getpid(), os.getppid()):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
PY_EOF

    /tmp/pipeline_verifier_bin >/tmp/pipeline_verifier.log 2>&1 &
    service_pid=$!

    cat > /tmp/test_final_state.py <<'PYTEST_EOF'
import random
import socket
import time

import pytest
import requests

HTTP_URL = "http://127.0.0.1:8080/clean"


def wait_for_ports():
    deadline = time.time() + 8
    for port in (8080, 8081):
        while True:
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                    break
            except OSError:
                if time.time() >= deadline:
                    pytest.fail(f"Service did not listen on port {port}")
                time.sleep(0.05)


def expected_clean(data):
    cols = len(data[0])
    energies = [sum(row[c] * row[c] for row in data) for c in range(cols)]
    selected = sorted(range(cols), key=lambda c: energies[c], reverse=True)[:2]
    return [
        [row[c] for c in selected]
        for row in data
        if all(-50.0 < value < 50.0 for value in row)
    ]


def assert_numeric_rows(actual, expected):
    assert isinstance(actual, list), "cleaned_data must be a list"
    assert len(actual) == len(expected), (
        f"Expected {len(expected)} records after anomaly removal, got {len(actual)}"
    )
    for row, wanted in zip(actual, expected):
        assert isinstance(row, list), f"Expected a row list, got {row!r}"
        assert len(row) == 2, f"Expected each record to have 2 dimensions, got {len(row)} for {row}"
        assert all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in row)
        assert row == pytest.approx(wanted, rel=1e-10, abs=1e-10)


def post_and_check(data):
    try:
        response = requests.post(HTTP_URL, json={"data": data}, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"HTTP request to {HTTP_URL} failed: {exc}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    try:
        result = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert "cleaned_data" in result, "Response JSON missing 'cleaned_data' key"
    assert_numeric_rows(result["cleaned_data"], expected_clean(data))


def test_tcp_status_endpoint():
    with socket.create_connection(("127.0.0.1", 8081), timeout=5) as connection:
        connection.sendall(b"STATUS auth_token=secret_123\n")
        response = connection.recv(1024)
        assert response == b"OK\n", f"Expected 'OK\\n', got {response!r}"


def test_original_http_case_and_values():
    data = [
        [10.0, 10.0, 0.1],
        [10.1, 9.9, 0.2],
        [10.2, 10.1, -0.1],
        [100.0, -50.0, 5.0],
    ]
    post_and_check(data)


def test_runtime_generated_cleaning_cases():
    rng = random.SystemRandom()
    for case in range(5):
        rows = 6 + case
        cols = 4 + (case % 2)
        scales = [rng.uniform(0.3, 7.0) for _ in range(cols)]
        data = [
            [round(rng.uniform(-4.0, 4.0) * scales[c], 7) for c in range(cols)]
            for _ in range(rows)
        ]

        # Add unpredictable anomalies. Their values also participate in the
        # component-energy calculation, as CleanDataset computes components first.
        anomaly1 = [round(rng.uniform(-8.0, 8.0), 7) for _ in range(cols)]
        anomaly1[rng.randrange(cols)] = rng.choice((-1.0, 1.0)) * rng.uniform(55.0, 130.0)
        data.insert(rng.randrange(len(data) + 1), anomaly1)

        if case % 2 == 0:
            anomaly2 = [round(rng.uniform(-10.0, 10.0), 7) for _ in range(cols)]
            anomaly2[rng.randrange(cols)] = rng.choice((-50.0, 50.0))
            data.insert(rng.randrange(len(data) + 1), anomaly2)

        post_and_check(data)


wait_for_ports()
PYTEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1
}

if run_verification; then
    reward=1
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0
