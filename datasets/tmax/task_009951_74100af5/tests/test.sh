#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'EOF' > /tmp/expected_num.go
package num

// #cgo CFLAGS: -g -Wall
// #include "algo.h"
import "C"

func ComputePolynomial(x float64) float64 {
	return float64(C.compute_polynomial(C.double(x)))
}
EOF

cat << 'EOF' > /tmp/expected_num_test.go
package num

import (
	"math"
	"testing"
	"testing/quick"
)

func TestComputePolynomialConcurrent(t *testing.T) {
	t.Parallel()

	property := func(x float64) bool {
		// constrain x to avoid infinity/NaN issues
		if x > 1000 || x < -1000 {
			return true
		}

		got := ComputePolynomial(x)
		expected := (3.0 * x * x * x) + (2.0 * x * x) + x

		// Allow small floating point differences
		return math.Abs(got-expected) < 0.0001
	}

	config := &quick.Config{
		MaxCount: 1000,
	}

	if err := quick.Check(property, config); err != nil {
		t.Error(err)
	}
}

func TestComputePolynomialConcurrent2(t *testing.T) {
	t.Parallel()
	// Duplicate test to force concurrency and trigger the race detector
	property := func(x float64) bool {
		if x > 1000 || x < -1000 { return true }
		got := ComputePolynomial(x)
		expected := (3.0 * x * x * x) + (2.0 * x * x) + x
		return math.Abs(got-expected) < 0.0001
	}
	config := &quick.Config{ MaxCount: 1000 }
	if err := quick.Check(property, config); err != nil {
		t.Error(err)
	}
}
EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile

REPO = "/home/user/numeric-lib"


def test_original_go_call_path_and_tests_are_intact():
    for actual, expected in [
        (os.path.join(REPO, "num.go"), "/tmp/expected_num.go"),
        (os.path.join(REPO, "num_test.go"), "/tmp/expected_num_test.go"),
    ]:
        assert os.path.isfile(actual), f"Required file {actual} does not exist"
        with open(actual, "rb") as f:
            actual_data = f.read()
        with open(expected, "rb") as f:
            expected_data = f.read()
        assert actual_data == expected_data, f"{actual} was modified; the original C call path and concurrent tests must remain intact"


def test_algo_c_fixed():
    path = os.path.join(REPO, "algo.c")
    assert os.path.isfile(path), f"File {path} does not exist"

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original regression assertion.
    assert "static double cache" not in content, "The 'static double cache' shared state is still present in algo.c"

    header = os.path.join(REPO, "algo.h")
    assert os.path.isfile(header), f"File {header} does not exist"
    with open(header, "r") as f:
        header_content = f.read()
    assert re.search(r"\bdouble\s+compute_polynomial\s*\(\s*double\s+[A-Za-z_]\w*\s*\)\s*;", header_content), \
        "algo.h no longer declares the required double compute_polynomial(double) ABI"


def test_submitted_c_implementation_under_thread_sanitizer():
    # Compile algo.c itself into a verifier-owned concurrent harness. The harness
    # declares the public ABI independently, so a modified header cannot redirect
    # calls away from the submitted implementation.
    harness = r'''
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

extern double compute_polynomial(double);

#define THREADS 8
#define ITERS 20000
static pthread_barrier_t barrier;
static volatile double sink;

static void *worker(void *arg) {
    long id = (long)arg;
    if (pthread_barrier_wait(&barrier) != 0 && errno != PTHREAD_BARRIER_SERIAL_THREAD) {
        return (void *)1;
    }
    for (long i = 0; i < ITERS; ++i) {
        double x = ((double)(((i * 7919) + id * 104729) % 200001) - 100000.0) / 100.0;
        double got = compute_polynomial(x);
        double expected = (3.0 * x * x * x) + (2.0 * x * x) + x;
        double tolerance = 1e-10 * (1.0 + fabs(expected));
        if (!isfinite(got) || fabs(got - expected) > tolerance) {
            fprintf(stderr, "wrong result for %.17g: got %.17g expected %.17g\n", x, got, expected);
            return (void *)1;
        }
        sink = got;
    }
    return NULL;
}

int main(void) {
    pthread_t threads[THREADS];
    if (pthread_barrier_init(&barrier, NULL, THREADS) != 0) return 2;
    for (long i = 0; i < THREADS; ++i)
        if (pthread_create(&threads[i], NULL, worker, (void *)i) != 0) return 3;
    int failed = 0;
    for (int i = 0; i < THREADS; ++i) {
        void *result = NULL;
        if (pthread_join(threads[i], &result) != 0 || result != NULL) failed = 1;
    }
    pthread_barrier_destroy(&barrier);
    return failed;
}
'''
    # errno is needed for the portable pthread_barrier_wait result check.
    harness = harness.replace("#include <math.h>", "#include <errno.h>\n#include <math.h>")
    with tempfile.TemporaryDirectory() as td:
        harness_path = os.path.join(td, "harness.c")
        binary_path = os.path.join(td, "check_algo")
        with open(harness_path, "w") as f:
            f.write(harness)
        build = subprocess.run(
            ["/usr/bin/gcc", "-std=c11", "-D_XOPEN_SOURCE=700", "-O1", "-g",
             "-fno-omit-frame-pointer", "-fsanitize=thread", "-no-pie", "-pthread",
             harness_path, os.path.join(REPO, "algo.c"), "-lm", "-o", binary_path],
            capture_output=True, text=True, timeout=60
        )
        assert build.returncode == 0, f"algo.c failed to compile with the required ABI:\n{build.stdout}\n{build.stderr}"
        env = os.environ.copy()
        env["TSAN_OPTIONS"] = "halt_on_error=1:exitcode=66"
        run = subprocess.run([binary_path], capture_output=True, text=True, env=env, timeout=60)
        output = run.stdout + run.stderr
        assert run.returncode == 0, f"Concurrent execution of algo.c failed or exposed a C data race:\n{output}"
        assert "ThreadSanitizer: data race" not in output, f"C data race detected:\n{output}"


def test_go_test_race_passes():
    assert os.path.isdir(REPO), f"Directory {REPO} does not exist"

    # Preserve the original repository race-test assertion.
    result = subprocess.run(
        ["/usr/bin/go", "test", "-race"],
        cwd=REPO,
        capture_output=True,
        text=True,
        timeout=120
    )

    assert result.returncode == 0, f"go test -race failed with output:\n{result.stdout}\n{result.stderr}"
    assert "WARNING: DATA RACE" not in result.stdout, "Data race still detected in go test output"
    assert "WARNING: DATA RACE" not in result.stderr, "Data race still detected in go test stderr"


def test_test_results_log_exists_and_correct():
    log_path = "/home/user/test_results.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist"

    with open(log_path, "r") as f:
        content = f.read()

    # Preserve the original successful-output assertions.
    assert re.search(r"ok\s+numeric-lib", content) is not None, f"Expected passing test output in {log_path}, but got:\n{content}"
    assert "WARNING: DATA RACE" not in content, f"Data race warning found in {log_path}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
