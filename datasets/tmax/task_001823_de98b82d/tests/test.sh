#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat


def test_server_bin_exists_and_executable():
    bin_path = "/home/user/app/server_bin"
    assert os.path.exists(bin_path), f"Binary {bin_path} does not exist."
    assert os.path.isfile(bin_path), f"{bin_path} is not a file."

    st = os.stat(bin_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Binary {bin_path} is not executable."


def test_models_package_created():
    models_path = "/home/user/app/models/models.go"
    assert os.path.exists(models_path), f"File {models_path} does not exist."
    assert os.path.isfile(models_path), f"{models_path} is not a file."

    with open(models_path, "r") as f:
        content = f.read()

    assert "package models" in content, "models.go does not declare 'package models'."
    assert re.search(r"type\s+Request\s+struct", content), "models.go does not contain 'type Request struct'."


def test_limiter_test_exists_and_is_substantive():
    test_path = "/home/user/app/limiter/limiter_test.go"
    assert os.path.exists(test_path), f"Test file {test_path} does not exist."
    assert os.path.isfile(test_path), f"{test_path} is not a file."

    with open(test_path, "r") as f:
        content = f.read()

    assert re.search(r"func\s+TestLimiterConcurrent\s*\(", content), \
        "limiter_test.go does not define TestLimiterConcurrent."
    assert "sync.WaitGroup" in content, "Test must use sync.WaitGroup."
    assert re.search(r"\bgo\s+", content), "Test does not start goroutines."
    assert re.search(r"\.Wait\s*\(", content), "Test does not wait for goroutines."
    assert re.search(r"\b10\b", content), "Test does not specify 10 goroutines."
    assert re.search(r"\b5\b", content), "Test does not assert the five-request limit."


def test_limiter_uses_concurrency_primitive():
    limiter_path = "/home/user/app/limiter/limiter.go"
    with open(limiter_path, "r") as f:
        content = f.read()
    assert re.search(r'"sync(?:/atomic)?"|\bchan\b', content), \
        "limiter.go does not use a Go concurrency primitive."


def test_test_results_log():
    log_path = "/home/user/test_results.log"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."
    assert os.path.isfile(log_path), f"{log_path} is not a file."

    with open(log_path, "r") as f:
        content = f.read()

    assert "PASS" in content, "test_results.log does not contain 'PASS', tests might have failed."
    assert "TestLimiterConcurrent" in content, "test_results.log does not indicate TestLimiterConcurrent was run."
TEST_EOF

run_checks() {
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || return 1

    cd /home/user/app || return 1
    go build -o server_bin main.go || return 1
    test -x /home/user/app/server_bin || return 1
    timeout 5 /home/user/app/server_bin >/tmp/server_output.txt 2>&1 || return 1

    verifier_test=$(mktemp /home/user/app/limiter/verifier_XXXXXX_test.go) || return 1
    trap 'rm -f "$verifier_test"' RETURN
    cat << 'GO_TEST_EOF' > "$verifier_test"
package limiter_test

import (
    "app/limiter"
    "app/models"
    "sync"
    "testing"
)

func TestVerifierLimiterBehavior(t *testing.T) {
    sequential := limiter.NewLimiter()
    req := models.Request{ID: "verifier"}
    for i := 0; i < 5; i++ {
        if !sequential.Allow(req) {
            t.Fatalf("sequential request %d was denied before the limit", i+1)
        }
    }
    for i := 0; i < 20; i++ {
        if sequential.Allow(req) {
            t.Fatalf("request after the first five was allowed")
        }
    }

    for round := 0; round < 200; round++ {
        l := limiter.NewLimiter()
        start := make(chan struct{})
        results := make(chan bool, 10)
        var wg sync.WaitGroup
        wg.Add(10)

        for i := 0; i < 10; i++ {
            go func(id int) {
                defer wg.Done()
                <-start
                results <- l.Allow(models.Request{ID: "concurrent"})
            }(i)
        }

        close(start)
        wg.Wait()
        close(results)

        allowed := 0
        denied := 0
        for result := range results {
            if result {
                allowed++
            } else {
                denied++
            }
        }
        if allowed != 5 || denied != 5 {
            t.Fatalf("round %d: got %d allowed and %d denied; want 5 and 5", round, allowed, denied)
        }

        for i := 0; i < 20; i++ {
            if l.Allow(req) {
                t.Fatalf("round %d: limiter allowed a request after reaching five", round)
            }
        }
    }
}
GO_TEST_EOF

    go test ./... -v -count=1 > /tmp/verifier_go_test.log 2>&1 || {
        cat /tmp/verifier_go_test.log
        return 1
    }
    cat /tmp/verifier_go_test.log
    grep -q -- '--- PASS: TestLimiterConcurrent' /tmp/verifier_go_test.log || return 1
    grep -q -- '--- PASS: TestVerifierLimiterBehavior' /tmp/verifier_go_test.log || return 1

    rm -f "$verifier_test"
    trap - RETURN
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
