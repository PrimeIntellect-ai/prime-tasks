#!/bin/bash
set -e
mkdir -p /logs/verifier
reward=0
trap 'rm -f /home/user/analyzer/zz_verifier_entropy_test.go; printf "%s\n" "$reward" > /logs/verifier/reward.txt' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re


def test_test_results_log():
    """Verify that test_results.log exists and contains PASS."""
    log_path = "/home/user/test_results.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."
    with open(log_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "PASS" in content, "Tests did not pass or 'PASS' is missing from test_results.log."


def test_proxy_test_log_header():
    """Verify that proxy_test.log exists and contains the required security header."""
    log_path = "/home/user/proxy_test.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."
    with open(log_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert re.search(r"X-Deployment-Sec:\s*Ready", content, re.IGNORECASE), "Missing security header 'X-Deployment-Sec: Ready' in proxy response."


def test_proxy_test_log_body():
    """Verify that proxy_test.log contains the correct entropy calculation output."""
    log_path = "/home/user/proxy_test.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."
    with open(log_path, "r", encoding="utf-8") as f:
        content = f.read()
    match = re.search(r'"entropy"\s*:\s*2(?:\.0)?', content)
    assert match is not None, "Incorrect entropy calculation or missing JSON response in proxy_test.log."


def test_source_code_structure():
    """Verify that the required source code directories and files exist."""
    assert os.path.isdir("/home/user/analyzer"), "/home/user/analyzer directory does not exist."
    assert os.path.isfile("/home/user/analyzer/go.mod"), "/home/user/analyzer/go.mod does not exist."
    assert os.path.isfile("/home/user/analyzer/entropy.go"), "/home/user/analyzer/entropy.go does not exist."
    assert os.path.isfile("/home/user/analyzer/entropy_test.go"), "/home/user/analyzer/entropy_test.go does not exist."
    assert os.path.isfile("/home/user/analyzer/main.go"), "/home/user/analyzer/main.go does not exist."
    assert os.path.isdir("/home/user/proxy"), "/home/user/proxy directory does not exist."
    assert os.path.isfile("/home/user/proxy/go.mod"), "/home/user/proxy/go.mod does not exist."
    assert os.path.isfile("/home/user/proxy/main.go"), "/home/user/proxy/main.go does not exist."
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short

[ "$(cd /home/user/analyzer && go list -m)" = "analyzer" ]
[ "$(cd /home/user/proxy && go list -m)" = "proxy" ]

# Run the agent's own tests before adding verifier-owned tests, and require that
# entropy_test.go actually contributes at least one Go test.
(cd /home/user/analyzer && timeout 90 go test -v ./... > /tmp/verifier_agent_tests.log)
(cd /home/user/analyzer && timeout 90 go test -list '^Test' .) | grep -q '^Test'

# Exercise the required exported function directly against independently
# calculated Shannon entropy values.
cat << 'GO_TEST_EOF' > /home/user/analyzer/zz_verifier_entropy_test.go
package main

import (
    "math"
    "testing"
)

func verifierExpectedEntropy(data []byte) float64 {
    if len(data) == 0 {
        return 0
    }
    var counts [256]int
    for _, b := range data {
        counts[int(b)]++
    }
    n := float64(len(data))
    result := 0.0
    for _, count := range counts {
        if count != 0 {
            p := float64(count) / n
            result -= p * math.Log2(p)
        }
    }
    return result
}

func TestVerifierCalculateEntropy(t *testing.T) {
    vectors := [][]byte{
        {},
        {0, 0, 0, 0},
        {0, 0x11, 0x22, 0x33},
        {0xff, 0xff, 0xff, 0x01},
        {3, 7, 3, 9, 7, 3, 11, 13, 11, 3, 19},
    }
    generated := make([]byte, 257)
    for i := range generated {
        generated[i] = byte((i*i + 31*i + 17) % 43)
    }
    vectors = append(vectors, generated)
    for i, data := range vectors {
        want := verifierExpectedEntropy(data)
        got := CalculateEntropy(data)
        if math.IsNaN(got) || math.IsInf(got, 0) || math.Abs(got-want) > 1e-10 {
            t.Fatalf("vector %d: CalculateEntropy()=%v, want %v", i, got, want)
        }
    }
}
GO_TEST_EOF
(cd /home/user/analyzer && timeout 90 go test ./...)
rm -f /home/user/analyzer/zz_verifier_entropy_test.go

(cd /home/user/analyzer && timeout 90 go build -o /tmp/verifier-analyzer .)
(cd /home/user/proxy && timeout 90 go build -o /tmp/verifier-proxy .)

# Stop any pre-existing listeners so the verifier tests the binaries built from
# the submitted source rather than stale agent-started processes.
python3 << 'PY_KILL'
import os
import signal
import time

ports = {8080, 9000}
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table, encoding="ascii") as f:
            next(f)
            for line in f:
                fields = line.split()
                local = fields[1]
                state = fields[3]
                port = int(local.rsplit(":", 1)[1], 16)
                if port in ports and state == "0A":
                    inodes.add(fields[9])
    except FileNotFoundError:
        pass

pids = set()
for name in os.listdir("/proc"):
    if not name.isdigit():
        continue
    fd_dir = f"/proc/{name}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                pids.add(int(name))
    except (FileNotFoundError, PermissionError):
        continue
for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
time.sleep(0.4)
for pid in pids:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY_KILL

nohup /tmp/verifier-analyzer >/tmp/verifier-analyzer.log 2>&1 </dev/null &
analyzer_pid=$!
for _ in $(seq 1 100); do
    if curl -sS --max-time 1 http://127.0.0.1:9000/ >/dev/null 2>&1; then break; fi
    kill -0 "$analyzer_pid"
    sleep 0.1
done
kill -0 "$analyzer_pid"

nohup /tmp/verifier-proxy >/tmp/verifier-proxy.log 2>&1 </dev/null &
proxy_pid=$!
for _ in $(seq 1 100); do
    if curl -sS --max-time 1 http://127.0.0.1:8080/ >/dev/null 2>&1; then break; fi
    kill -0 "$proxy_pid"
    sleep 0.1
done
kill -0 "$proxy_pid"

# Send independently generated requests to both services and validate the
# numerical response and the proxy-added response header.
python3 << 'PY_INTEGRATION'
import collections
import json
import math
import urllib.request


def expected(raw):
    if not raw:
        return 0.0
    counts = collections.Counter(raw)
    n = len(raw)
    return -sum((count / n) * math.log2(count / n) for count in counts.values())

vectors = [
    bytes.fromhex("00112233"),
    bytes.fromhex("ffffffffffffff01"),
    bytes((i * i + 19 * i + 5) % 29 for i in range(113)),
]

for raw in vectors:
    payload = json.dumps({"data": raw.hex()}).encode("ascii")
    want = expected(raw)
    for url, through_proxy in (
        ("http://127.0.0.1:9000/entropy", False),
        ("http://127.0.0.1:8080/api/entropy", True),
    ):
        request = urllib.request.Request(
            url,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=3) as response:
            if response.status != 200:
                raise AssertionError(f"{url} returned HTTP {response.status}")
            if through_proxy and response.headers.get("X-Deployment-Sec") != "Ready":
                raise AssertionError("proxy response lacks X-Deployment-Sec: Ready")
            body = json.loads(response.read().decode("utf-8"))
        got = body.get("entropy")
        if not isinstance(got, (int, float)) or not math.isfinite(got):
            raise AssertionError(f"invalid entropy response from {url}: {body!r}")
        if abs(float(got) - want) > 1e-9:
            raise AssertionError(f"wrong entropy from {url}: got {got}, want {want}")
PY_INTEGRATION

kill -0 "$analyzer_pid"
kill -0 "$proxy_pid"
reward=1
