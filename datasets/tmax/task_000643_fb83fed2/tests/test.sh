#!/bin/bash
mkdir -p /logs/verifier

HIDDEN_TEST=/home/user/stats/verifier_hidden_test.go
VERIFIER_MARKER=/tmp/stats-verifier-marker-$$
export VERIFIER_MARKER
rm -f "$VERIFIER_MARKER"
trap 'rm -f "$HIDDEN_TEST" "$VERIFIER_MARKER"' EXIT

cat << 'GO_EOF' > "$HIDDEN_TEST"
package stats

import (
	cryptorand "crypto/rand"
	"encoding/binary"
	"math"
	mathrand "math/rand"
	"os"
	"reflect"
	"testing"
)

func verifierExpected(data []float64) []bool {
	if len(data) == 0 {
		return nil
	}
	var sum float64
	for _, value := range data {
		sum += value
	}
	mean := sum / float64(len(data))

	var variance float64
	for _, value := range data {
		delta := value - mean
		variance += delta * delta
	}
	stddev := math.Sqrt(variance / float64(len(data)))
	result := make([]bool, len(data))
	if stddev == 0 {
		return result
	}
	for i, value := range data {
		result[i] = math.Abs((value-mean)/stddev) > 1.5
	}
	return result
}

func TestVerifierEnvironment(t *testing.T) {
	if os.Getenv("STATS_ENV") != "test" {
		t.Fatalf("test target did not run tests with STATS_ENV=test")
	}
	marker := os.Getenv("VERIFIER_MARKER")
	if marker == "" {
		t.Fatal("VERIFIER_MARKER was not propagated to the test process")
	}
	if err := os.WriteFile(marker, []byte("hidden tests executed"), 0600); err != nil {
		t.Fatalf("could not write verifier marker: %v", err)
	}
}

func TestVerifierDetectAnomalies(t *testing.T) {
	cases := [][]float64{
		nil,
		{},
		{7},
		{4, 4, 4, 4, 4},
		{10, 10, 10, 10, 110},
		{-110, -10, -10, -10, -10},
		{-8, -3, 0, 2, 4, 17},
		{0.25, 0.5, 0.75, 1, 9.5},
		{100, 101, 99, 100.5, 100.25, 63},
	}

	var seedBytes [8]byte
	if _, err := cryptorand.Read(seedBytes[:]); err != nil {
		t.Fatalf("cannot obtain random seed: %v", err)
	}
	rng := mathrand.New(mathrand.NewSource(int64(binary.LittleEndian.Uint64(seedBytes[:]))))
	for len(cases) < 209 {
		n := 2 + rng.Intn(39)
		data := make([]float64, n)
		for i := range data {
			data[i] = float64(rng.Intn(1601)-800)/4 + float64(i%3)/10
		}
		if rng.Intn(2) == 0 && n >= 4 {
			baseline := float64(rng.Intn(201)-100) / 2
			for i := range data {
				data[i] = baseline + float64(rng.Intn(9)-4)/20
			}
			data[rng.Intn(n)] += float64(80 + rng.Intn(200))
		}

		// Avoid accidental cases numerically indistinguishable from the strict threshold.
		var sum float64
		for _, value := range data {
			sum += value
		}
		mean := sum / float64(n)
		var variance float64
		for _, value := range data {
			variance += (value - mean) * (value - mean)
		}
		stddev := math.Sqrt(variance / float64(n))
		borderline := false
		if stddev != 0 {
			for _, value := range data {
				if math.Abs(math.Abs((value-mean)/stddev)-1.5) < 1e-9 {
					borderline = true
					break
				}
			}
		}
		if !borderline {
			cases = append(cases, data)
		}
	}

	for i, data := range cases {
		want := verifierExpected(data)
		got := DetectAnomalies(data)
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("case %d, data=%v: expected %v, got %v", i, data, want, got)
		}
	}
}
GO_EOF

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import subprocess
import pytest

ROOT = "/home/user/stats"
MARKER = os.environ["VERIFIER_MARKER"]


def test_success_file_exists_and_content():
    path = "/home/user/success.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "ALL TESTS PASSED", f"Expected 'ALL TESTS PASSED', got '{content}'"


def test_makefile_fixed():
    path = os.path.join(ROOT, "Makefile")
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "STATS_ENV=test" in content, "Makefile does not set STATS_ENV=test for the test target."


def test_stats_go_fixed():
    path = os.path.join(ROOT, "stats.go")
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "(x - stddev) / mean" not in content, "stats.go still contains the buggy Z-score formula."
    assert "mean" in content and "stddev" in content, "stats.go seems to be missing required variables."


def test_make_test_passes_and_executes_tests():
    if os.path.exists(MARKER):
        os.remove(MARKER)
    env = os.environ.copy()
    env["GOFLAGS"] = "-count=1"
    try:
        result = subprocess.run(
            ["make", "test"],
            cwd=ROOT,
            env=env,
            capture_output=True,
            text=True,
            check=True,
            timeout=120,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"'make test' failed with exit code {e.returncode}.\nStdout: {e.stdout}\nStderr: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail("'make test' timed out")
    assert "ok" in result.stdout or "PASS" in result.stdout, "Test output does not indicate success."
    assert os.path.isfile(MARKER), "The Makefile test target did not actually execute the Go tests."


def test_direct_behavioral_suite_passes():
    env = os.environ.copy()
    env["STATS_ENV"] = "test"
    result = subprocess.run(
        ["go", "test", "-count=1", "./..."],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"Behavioral Go tests failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
