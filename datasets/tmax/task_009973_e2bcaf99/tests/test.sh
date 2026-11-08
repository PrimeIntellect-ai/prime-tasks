#!/bin/bash
mkdir -p /logs/verifier

APP_DIR=/home/user/sec-app
NONCE=$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
if [ -z "$NONCE" ]; then
    NONCE="$$$(date +%s)"
fi
VERIFIER_TEST="$APP_DIR/verifier_${NONCE}_test.go"
MARKER="/tmp/sec_app_verifier_${NONCE}.marker"
MAKE_OUTPUT="/tmp/sec_app_make_${NONCE}.out"
PYTEST_FILE="/tmp/test_final_state_${NONCE}.py"
score=1

cleanup() {
    rm -f "$VERIFIER_TEST" "$MARKER" "$MAKE_OUTPUT" "$PYTEST_FILE"
}
trap cleanup EXIT

cat > "$VERIFIER_TEST" <<EOF
package main

import (
    "fmt"
    "net/http"
    "net/http/httptest"
    "os"
    "strings"
    "testing"
)

func TestVerifierRateLimitBehavior(t *testing.T) {
    requestCount = 0
    handler := RateLimitMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(http.StatusOK)
    }))

    for i := 1; i <= 6; i++ {
        req := httptest.NewRequest(http.MethodGet, "http://example.com/verifier", nil)
        req.Header.Set("X-Token", "secret")
        recorder := httptest.NewRecorder()
        handler.ServeHTTP(recorder, req)

        expected := http.StatusOK
        if i == 6 {
            expected = http.StatusTooManyRequests
        }
        if recorder.Code != expected {
            t.Fatalf("request %d: expected status %d, got %d", i, expected, recorder.Code)
        }
    }

    maps, err := os.ReadFile("/proc/self/maps")
    if err != nil {
        t.Fatalf("cannot inspect loaded shared libraries: %v", err)
    }
    if !strings.Contains(string(maps), "libtokencheck.so") {
        t.Fatal("libtokencheck.so is not dynamically loaded by the test process")
    }

    if err := os.WriteFile("$MARKER", []byte(fmt.Sprint("$NONCE")), 0600); err != nil {
        t.Fatalf("cannot write verifier marker: %v", err)
    }
}
EOF
if [ $? -ne 0 ]; then
    score=0
fi

rm -f "$APP_DIR/test_results.log" "$MARKER"

if [ "$score" -eq 1 ]; then
    (
        cd "$APP_DIR" &&
        timeout 120s env -u LD_LIBRARY_PATH -u LIBRARY_PATH -u LD_PRELOAD \
            -u CGO_CFLAGS -u CGO_CPPFLAGS -u CGO_CXXFLAGS -u CGO_LDFLAGS \
            -u GOFLAGS GOENV=off make test
    ) >"$MAKE_OUTPUT" 2>&1
    if [ $? -ne 0 ]; then
        score=0
    fi
fi

if [ ! -f "$MARKER" ] || [ "$(cat "$MARKER" 2>/dev/null)" != "$NONCE" ]; then
    score=0
fi

cat > "$PYTEST_FILE" <<'PYEOF'
import os
import re

APP_DIR = "/home/user/sec-app"
LOG_FILE = os.path.join(APP_DIR, "test_results.log")
MIDDLEWARE_FILE = os.path.join(APP_DIR, "middleware.go")


def test_test_results_log_exists():
    assert os.path.isfile(LOG_FILE), f"The file {LOG_FILE} does not exist. Did you run 'make test'?"


def test_test_results_log_passed():
    with open(LOG_FILE, "r") as f:
        content = f.read()

    assert "FAIL" not in content, "The test results log contains failures."
    assert "PASS" in content, "The test results log does not indicate a successful test run (missing 'PASS')."
    assert "TestVerifierRateLimitBehavior" in content, "make test did not run the verifier's behavioral Go test."


def test_middleware_logic_fixed():
    assert os.path.isfile(MIDDLEWARE_FILE), f"The file {MIDDLEWARE_FILE} does not exist."

    with open(MIDDLEWARE_FILE, "r") as f:
        content = f.read()

    assert "requestCount > 10" not in content, "The rate limit logic still contains 'requestCount > 10'."
    match = re.search(r'requestCount\s*(>|>=|==)\s*([56])', content)
    assert match is not None, "Could not find the corrected rate limiting logic in middleware.go (expected condition like 'requestCount > 5')."


def test_cgo_or_makefile_fixed():
    # The injected Go test is required to execute through `make test` and confirms
    # from /proc/self/maps that libtokencheck.so was dynamically loaded.
    pass
PYEOF

if ! python3 -m pytest "$PYTEST_FILE" -x --tb=short 2>&1; then
    score=0
fi

if [ "$score" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
