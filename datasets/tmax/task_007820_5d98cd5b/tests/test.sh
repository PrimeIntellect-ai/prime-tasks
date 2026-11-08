#!/bin/bash
set +e
mkdir -p /logs/verifier
PROJECT_DIR=/home/user/project
BACKUP=$(mktemp)
TEST_FILE="$PROJECT_DIR/tests/test_client.py"
if [ -f "$TEST_FILE" ]; then
    cp "$TEST_FILE" "$BACKUP"
    HAD_TEST=1
else
    HAD_TEST=0
fi
SERVER_PID=""

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    pkill -x server 2>/dev/null || true
    if [ "$HAD_TEST" = 1 ]; then
        cp "$BACKUP" "$TEST_FILE"
    else
        rm -f "$TEST_FILE"
    fi
    rm -f "$BACKUP" /tmp/ci-proof-* /tmp/server-proof-* /tmp/test_final_state.py /tmp/verifier_client.py
}
trap cleanup EXIT

run_checks() (
    set -e

    cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re

PROJECT_DIR = "/home/user/project"

def test_mathparser_h_fixed():
    path = os.path.join(PROJECT_DIR, "include", "mathparser.h")
    assert os.path.isfile(path), f"Header file {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    assert 'extern "C"' in content, (
        f"The file {path} does not contain 'extern \"C\"'. "
        "This is required to fix the C/C++ linkage issue."
    )

def test_mathparser_c_fixed():
    path = os.path.join(PROJECT_DIR, "c_src", "mathparser.c")
    assert os.path.isfile(path), f"C source file {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    # Check that the bug 'a / b' is removed and replaced with 'b / a' or similar valid logic.
    # We look for the division operation.
    assert re.search(r'b\s*/\s*a', content) is not None, (
        f"The file {path} does not seem to have the division bug fixed. "
        "Expected to find 'b / a' (or equivalent) for the division operation."
    )
    assert re.search(r'a\s*/\s*b', content) is None, (
        f"The file {path} still contains the buggy 'a / b' division logic."
    )

def test_ci_success_log():
    log_path = os.path.join(PROJECT_DIR, "ci_success.log")
    assert os.path.isfile(log_path), (
        f"The log file {log_path} does not exist. "
        "Did you redirect the output of 'make ci' to this file?"
    )

    with open(log_path, "r") as f:
        content = f.read()

    expected_output = "PASS: 10 2 / = 5.0"
    assert expected_output in content, (
        f"The log file {log_path} does not contain the expected success output: '{expected_output}'. "
        "Make sure the tests passed successfully and the output was redirected."
    )
TEST_EOF

    cd "$PROJECT_DIR"
    python3 -m pytest /tmp/test_final_state.py -x --tb=short

    # The submitted log must contain the complete successful integration output,
    # not merely the single division line checked by the original assertions.
    grep -Fq 'PASS: 3 4 + = 7.0' ci_success.log
    grep -Fq 'PASS: 10 2 / = 5.0' ci_success.log
    grep -Fq 'PASS: 5 2 * 3 - = 7.0' ci_success.log

    # Compile the C implementation and call it from a separately compiled C++
    # translation unit. This semantically verifies both C/C++ linkage and RPN math.
    BUILD_DIR=$(mktemp -d)
    trap 'rm -rf "$BUILD_DIR"' RETURN
    gcc -fPIC -I./include -shared -o "$BUILD_DIR/libverify_mathparser.so" c_src/mathparser.c
    cat > "$BUILD_DIR/link_test.cpp" <<'CPP_EOF'
#include "mathparser.h"
#include <cmath>
#include <cstdlib>
#include <string>

static void check(const char *expr, double expected) {
    double actual = evaluate_rpn(expr);
    if (!std::isfinite(actual) || std::fabs(actual - expected) > 1e-9) std::exit(1);
}

int main() {
    check("81 9 /", 9.0);
    check("7 13 -", -6.0);
    check("6 11 *", 66.0);
    check("17 8 +", 25.0);
    check("9 2 / 5 +", 9.5);
    return 0;
}
CPP_EOF
    g++ -I./include -o "$BUILD_DIR/link_test" "$BUILD_DIR/link_test.cpp" \
        -L"$BUILD_DIR" -lverify_mathparser -Wl,-rpath,"$BUILD_DIR"
    "$BUILD_DIR/link_test"

    # Install a verifier-controlled integration client. A successful ci target must
    # really launch a TCP server and invoke tests/test_client.py; printed PASS text
    # alone cannot create the unpredictable proof file.
    MARKER="verified-$RANDOM-$$-$(date +%s%N)"
    PROOF="/tmp/ci-proof-$$-$RANDOM"
    cat > /tmp/verifier_client.py <<'PY_EOF'
import math
import os
import random
import socket
import sys
import time

marker = os.environ["VERIFY_MARKER"]
proof = os.environ["VERIFY_PROOF"]
seed = int.from_bytes(os.urandom(16), "big")
rng = random.Random(seed)
cases = []
for op in "+-*/":
    for _ in range(4):
        left = rng.randint(2, 90)
        right = rng.randint(2, 20)
        expected = {
            "+": lambda: left + right,
            "-": lambda: left - right,
            "*": lambda: left * right,
            "/": lambda: left / right,
        }[op]()
        cases.append((f"{left} {right} {op}", expected))

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
deadline = time.time() + 8
while True:
    try:
        sock.connect(("127.0.0.1", 8080))
        break
    except OSError:
        if time.time() >= deadline:
            raise
        time.sleep(0.05)

for expression, expected in cases:
    sock.sendall(expression.encode("ascii"))
    data = sock.recv(1024)
    if not data:
        raise RuntimeError("server closed the connection without a result")
    actual = float(data.decode("ascii").strip())
    if not math.isfinite(actual) or abs(actual - expected) > 0.001:
        raise AssertionError(f"{expression}: got {actual}, expected {expected}")

sock.sendall(b"QUIT")
sock.close()
with open(proof, "x", encoding="utf-8") as out:
    out.write(marker)
print(marker)
PY_EOF
    cp /tmp/verifier_client.py tests/test_client.py

    pkill -x server 2>/dev/null || true
    sleep 0.2
    make clean
    VERIFY_MARKER="$MARKER" VERIFY_PROOF="$PROOF" timeout 35s make ci > /tmp/verifier_make_ci.log 2>&1
    test -f "$PROOF"
    test "$(cat "$PROOF")" = "$MARKER"
    grep -Fq "$MARKER" /tmp/verifier_make_ci.log
    test ! -e server.pid

    # Ensure make produced real native artifacts, then directly exercise the built
    # server independently of whatever commands the ci recipe chose to run.
    test -f lib/libmathparser.so
    test -x bin/server
    file lib/libmathparser.so | grep -q 'ELF.*shared object'
    file bin/server | grep -q 'ELF.*executable\|ELF.*pie executable'

    PROOF2="/tmp/server-proof-$$-$RANDOM"
    MARKER2="direct-$RANDOM-$$-$(date +%s%N)"
    VERIFY_MARKER="$MARKER2" VERIFY_PROOF="$PROOF2" ./bin/server > /tmp/verifier_server.log 2>&1 &
    SERVER_PID=$!
    export SERVER_PID
    VERIFY_MARKER="$MARKER2" VERIFY_PROOF="$PROOF2" timeout 15s python3 /tmp/verifier_client.py
    wait "$SERVER_PID"
    SERVER_PID=""
    test -f "$PROOF2"
    test "$(cat "$PROOF2")" = "$MARKER2"

    # No server or stale orchestration state may remain after the successful run.
    python3 - <<'PY_EOF'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 8080))
s.close()
PY_EOF
)

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
