#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'GO_TEST_EOF' > /home/user/cache-node/verifier_generated_test.go
package cache

import "testing"

var verifierSink uint32
var verifierBenchData = func() []byte {
	b := make([]byte, 10*1024*1024)
	var x uint32 = 0x9e3779b9
	for i := range b {
		x ^= x << 13
		x ^= x >> 17
		x ^= x << 5
		b[i] = byte(x)
	}
	return b
}()

func verifierDJB2(data []byte) uint32 {
	var hash uint32 = 5381
	for _, b := range data {
		hash = hash*33 + uint32(b)
	}
	return hash
}

func TestVerifierHashCorrectness(t *testing.T) {
	inputs := [][]byte{
		nil,
		{},
		{0},
		{1},
		{0, 1, 2, 3, 4, 5},
		[]byte("branch == \\"main\\" && size < 50000"),
	}

	var x uint32 = 0x6d2b79f5
	for _, n := range []int{2, 7, 31, 32, 33, 255, 1024, 65537, 1048579} {
		b := make([]byte, n)
		for i := range b {
			x ^= x << 13
			x ^= x >> 17
			x ^= x << 5
			b[i] = byte(x)
		}
		inputs = append(inputs, b)
	}
	inputs = append(inputs, verifierBenchData)

	for i, input := range inputs {
		want := verifierDJB2(input)
		if got := HashGo(input); got != want {
			t.Fatalf("HashGo case %d: got %08x, want %08x", i, got, want)
		}
		if got := HashCGO(input); got != want {
			t.Fatalf("HashCGO case %d: got %08x, want %08x", i, got, want)
		}
	}
}

func TestVerifierEvaluateRule(t *testing.T) {
	tests := []struct {
		expr   string
		branch string
		size   int
		want   bool
	}{
		{`branch == "main"`, "main", 1, true},
		{`branch == "main"`, "dev", 1, false},
		{`branch != "main"`, "dev", 1, true},
		{`size < 50000`, "main", 49999, true},
		{`size < 50000`, "main", 50000, false},
		{`size > 10`, "main", 11, true},
		{`branch == "main" && size < 50000`, "main", 1000, true},
		{`branch == "main" && size < 50000`, "main", 60000, false},
		{`branch == "main" || branch == "release"`, "release", 1, true},
		{`branch == "main" || branch == "release" && size > 10`, "release", 5, false},
		{`  branch != "dev"  &&  size > 0 `, "main", 1, true},
	}
	for _, tc := range tests {
		got, err := EvaluateRule(tc.expr, tc.branch, tc.size)
		if err != nil {
			t.Errorf("EvaluateRule(%q) returned unexpected error: %v", tc.expr, err)
			continue
		}
		if got != tc.want {
			t.Errorf("EvaluateRule(%q, %q, %d) = %v, want %v", tc.expr, tc.branch, tc.size, got, tc.want)
		}
	}

	for _, expr := range []string{"", `branch = "main"`, `branch ==`, `unknown == "x"`, `size <= 10`, `branch == "unterminated`} {
		if _, err := EvaluateRule(expr, "main", 10); err == nil {
			t.Errorf("EvaluateRule(%q) should return an error", expr)
		}
	}
}

func BenchmarkVerifierGoReference(b *testing.B) {
	for i := 0; i < b.N; i++ {
		verifierSink = verifierDJB2(verifierBenchData)
	}
}

func BenchmarkVerifierCGO(b *testing.B) {
	for i := 0; i < b.N; i++ {
		verifierSink = HashCGO(verifierBenchData)
	}
}
GO_TEST_EOF
trap 'rm -f /home/user/cache-node/verifier_generated_test.go' EXIT

cat <<'PY_TEST_EOF' > /tmp/test_final_state.py
import http.client
import json
import os
import re
import statistics
import subprocess
import time
import urllib.error
import urllib.request
import pytest

WORKSPACE_DIR = "/home/user/cache-node"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def test_hash_correctness_and_rule_evaluation():
    result = run(["go", "test", "-run", "^TestVerifier", "-count=1"], cwd=WORKSPACE_DIR)
    assert result.returncode == 0, f"Go behavioral tests failed:\n{result.stdout}\n{result.stderr}"


def benchmark_values(output, first_name, second_name):
    first = []
    second = []
    for line in output.splitlines():
        fields = line.split()
        if len(fields) < 3:
            continue
        try:
            value = float(fields[2])
        except ValueError:
            continue
        if first_name in fields[0]:
            first.append(value)
        elif second_name in fields[0]:
            second.append(value)
    return first, second


def test_benchmark_speedup():
    # Preserve the benchmark required by the original verifier.
    result = run(["go", "test", "-bench=BenchmarkHash", "-benchmem"], cwd=WORKSPACE_DIR)
    assert result.returncode == 0, f"Benchmark command failed. Stderr: {result.stderr}\nStdout: {result.stdout}"
    go_times, cgo_times = benchmark_values(result.stdout, "BenchmarkHashGo", "BenchmarkHashCGO")
    assert go_times, f"Could not find BenchmarkHashGo results in output:\n{result.stdout}"
    assert cgo_times, f"Could not find BenchmarkHashCGO results in output:\n{result.stdout}"
    assert cgo_times[0] > 0, "CGO benchmark time must be greater than 0"
    speedup = go_times[0] / cgo_times[0]
    assert speedup >= 4.0, f"Speedup is {speedup:.2f}x (Go: {go_times[0]} ns/op, CGO: {cgo_times[0]} ns/op). Expected >= 4.0x"

    # Benchmark against verifier-owned DJB2 code so slowing or replacing HashGo
    # cannot manufacture the requested speedup.
    result = run([
        "go", "test", "-run", "^$", "-bench", "^BenchmarkVerifier",
        "-benchtime=300ms", "-count=3"
    ], cwd=WORKSPACE_DIR)
    assert result.returncode == 0, f"Independent benchmark failed:\n{result.stdout}\n{result.stderr}"
    refs, cgos = benchmark_values(result.stdout, "BenchmarkVerifierGoReference", "BenchmarkVerifierCGO")
    assert len(refs) == 3 and len(cgos) == 3, f"Missing independent benchmark results:\n{result.stdout}"
    assert all(v > 0 for v in cgos)
    independent_speedup = statistics.median(refs) / statistics.median(cgos)
    assert independent_speedup >= 4.0, (
        f"Independent speedup is {independent_speedup:.2f}x "
        f"(Go median {statistics.median(refs)} ns/op, CGO median {statistics.median(cgos)} ns/op); expected >= 4.0x"
    )


def request(port, source_ip, body, path="/api/upload", method="POST"):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=3, source_address=(source_ip, 0))
    headers = {"Content-Type": "application/json"}
    try:
        conn.request(method, path, body=body, headers=headers)
        response = conn.getresponse()
        response.read()
        return response.status
    finally:
        conn.close()


def redis_dbsize():
    total = 0
    for db in range(16):
        result = run(["redis-cli", "-n", str(db), "DBSIZE"])
        assert result.returncode == 0, f"Unable to query Redis DB {db}: {result.stderr}"
        total += int(result.stdout.strip())
    return total


def test_nginx_configuration_targets_go_service():
    result = run(["nginx", "-T"])
    assert result.returncode == 0, f"nginx configuration is invalid: {result.stderr}"
    config = result.stdout + result.stderr
    assert re.search(r"listen\s+(?:[^;]*:)?8080\b", config), "Nginx is not configured to listen on port 8080"
    assert re.search(r"location\s+(?:\^~\s+)?/api/", config), "Nginx has no /api/ location"
    assert re.search(r"proxy_pass\s+http://(?:localhost|127\.0\.0\.1):9000", config), "Nginx /api/ traffic is not proxy-passed to port 9000"


def test_exact_ip_rate_limit_and_redis_usage_through_nginx():
    ping = run(["redis-cli", "PING"])
    assert ping.returncode == 0 and ping.stdout.strip() == "PONG", "Redis is not running"
    flushed = run(["redis-cli", "FLUSHALL"])
    assert flushed.returncode == 0, flushed.stderr

    # Begin near the start of a wall-clock second to avoid crossing a fixed
    # one-second window during this localhost burst.
    fraction = time.time() % 1
    if fraction > 0.20:
        time.sleep(1.05 - fraction)

    payload = json.dumps({"branch": "main", "size": 1000}).encode()
    statuses = [request(8080, "127.0.0.2", payload) for _ in range(6)]
    assert all(200 <= status < 300 for status in statuses[:5]), f"First five requests must succeed: {statuses}"
    assert statuses[5] == 429, f"Sixth request from one IP must be 429: {statuses}"

    # A different actual TCP source address must have its own allowance, while
    # the exhausted source remains blocked.
    other = request(8080, "127.0.0.3", payload)
    exhausted = request(8080, "127.0.0.2", payload)
    assert 200 <= other < 300, f"A different client IP was not independently limited: {other}"
    assert exhausted == 429, f"Exhausted client IP unexpectedly regained allowance: {exhausted}"
    assert redis_dbsize() > 0, "Requests did not create any Redis rate-limit state"


def test_request_body_is_parsed():
    result = run(["redis-cli", "FLUSHALL"])
    assert result.returncode == 0
    status = request(8080, "127.0.0.4", b'{not valid json')
    assert status == 400, f"Malformed JSON should be rejected with HTTP 400, got {status}"


def test_nginx_proxy_and_rate_limiting():
    # Preserve the original end-to-end assertion as well as the stricter test.
    url = "http://localhost:8080/api/upload"
    data = json.dumps({"branch": "main", "size": 1000}).encode("utf-8")
    time.sleep(1.5)
    responses = []
    for _ in range(8):
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
        try:
            resp = urllib.request.urlopen(req, timeout=2)
            responses.append(resp.status)
        except urllib.error.HTTPError as exc:
            responses.append(exc.code)
        except urllib.error.URLError as exc:
            pytest.fail(f"Failed to connect to Nginx at {url}: {exc.reason}")
    assert 429 in responses, f"Expected HTTP 429, got {responses}"
    assert any(isinstance(r, int) and 200 <= r < 300 for r in responses), f"Expected a successful request, got {responses}"


def test_go_service_running_on_9000():
    url = "http://localhost:9000/api/upload"
    data = json.dumps({"branch": "main", "size": 1000}).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
    try:
        resp = urllib.request.urlopen(req, timeout=2)
        status = resp.status
    except urllib.error.HTTPError as exc:
        status = exc.code
    except urllib.error.URLError as exc:
        pytest.fail(f"Go service is not listening on port 9000: {exc.reason}")
    assert status in [200, 201, 202, 429], f"Unexpected status code from Go service: {status}"
PY_TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
