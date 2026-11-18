#!/bin/bash
mkdir -p /logs/verifier

DYNAMIC_TEST="/home/user/aggregator/ws/zz_verifier_dynamic_test.go"
ok=1

cleanup() {
    rm -f "$DYNAMIC_TEST"
}
trap cleanup EXIT

# The agent may only modify the two named source files, so it must not supply
# the verifier test itself.
if [ -e "$DYNAMIC_TEST" ]; then
    echo "Unexpected verifier test path already exists: $DYNAMIC_TEST" >&2
    ok=0
else
    export DYNAMIC_TEST
    python3 - <<'PY' || ok=0
import json
import os
import random
import secrets

path = os.environ["DYNAMIC_TEST"]
rng = random.SystemRandom()
tag = secrets.token_hex(6).upper()
symbol_a = "VX" + tag
symbol_b = "QZ" + secrets.token_hex(6).upper()
amounts_a = [rng.randint(2, 30) for _ in range(3)]
amounts_b = [rng.randint(2, 30) for _ in range(2)]

events = [
    {"symbol": symbol_a, "price": 101.25, "amount": amounts_a[0]},
    {"symbol": symbol_b, "price": 207.75, "amount": amounts_b[0]},
    {"symbol": symbol_a, "price": 99.125, "amount": amounts_a[1]},
    {"symbol": symbol_b, "price": 208.5, "amount": amounts_b[1]},
    {"symbol": symbol_a, "price": 103.875, "amount": amounts_a[2]},
]
expected_a = sum(amounts_a)
expected_b = sum(amounts_b)
message_literals = ",\n\t\t".join(json.dumps(json.dumps(e, separators=(",", ":"))) for e in events)

source = r'''package ws_test

import (
    "net/http"
    "net/http/httptest"
    "strings"
    "testing"
    "time"

    "aggregator/ws"
    "github.com/gorilla/websocket"
)

func TestVerifierDynamicStreamAndNonblockingStart(t *testing.T) {
    messages := []string{
        __MESSAGES__
    }

    upgrader := websocket.Upgrader{}
    server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        conn, err := upgrader.Upgrade(w, r, nil)
        if err != nil {
            return
        }
        defer conn.Close()

        // Send one message and deliberately leave the stream idle. A Start
        // implementation that performs its read loop on the caller blocks here.
        _ = conn.WriteMessage(websocket.TextMessage, []byte(messages[0]))
        time.Sleep(400 * time.Millisecond)
        for _, message := range messages[1:] {
            _ = conn.WriteMessage(websocket.TextMessage, []byte(message))
            time.Sleep(8 * time.Millisecond)
        }
        time.Sleep(100 * time.Millisecond)
    }))
    defer server.Close()

    wsURL := "ws" + strings.TrimPrefix(server.URL, "http")
    conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
    if err != nil {
        t.Fatalf("dial failed: %v", err)
    }
    defer conn.Close()

    client := ws.NewClient(conn)
    returned := make(chan struct{})
    go func() {
        client.Start()
        close(returned)
    }()

    select {
    case <-returned:
    case <-time.After(150 * time.Millisecond):
        t.Fatal("Start blocked while the WebSocket stream remained open")
    }

    deadline := time.Now().Add(2 * time.Second)
    for time.Now().Before(deadline) {
        stats := client.GetStats()
        if len(stats) == 2 && stats[__SYMBOL_A__] == __EXPECTED_A__ && stats[__SYMBOL_B__] == __EXPECTED_B__ {
            return
        }
        time.Sleep(10 * time.Millisecond)
    }

    stats := client.GetStats()
    t.Fatalf("unexpected aggregation for randomized decimal-price stream: got %#v; want %s=%d and %s=%d only",
        stats, __SYMBOL_A__, __EXPECTED_A__, __SYMBOL_B__, __EXPECTED_B__)
}
'''
source = source.replace("__MESSAGES__", message_literals)
source = source.replace("__SYMBOL_A__", json.dumps(symbol_a))
source = source.replace("__SYMBOL_B__", json.dumps(symbol_b))
source = source.replace("__EXPECTED_A__", str(expected_a))
source = source.replace("__EXPECTED_B__", str(expected_b))

with open(path, "x", encoding="utf-8") as f:
    f.write(source)
PY
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess


def test_test_results_log_exists():
    log_path = "/home/user/test_results.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist. Did you save the test output?"


def test_test_results_log_content():
    log_path = "/home/user/test_results.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist."
    with open(log_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "PASS" in content, "The test_results.log does not contain 'PASS'."
    assert "FAIL" not in content, "The test_results.log contains 'FAIL'."
    assert re.search(r"(?m)^=== RUN\s+TestIntegration\s*$", content), \
        "The log is not verbose go test output for TestIntegration."
    assert re.search(r"(?m)^--- PASS: TestIntegration\b", content), \
        "The log does not show TestIntegration passing."
    assert re.search(r"(?m)^PASS\s*$", content), \
        "The log does not contain the standard successful package status."
    assert re.search(r"(?m)^ok\s+aggregator(?:\s|$)", content), \
        "The log does not show the aggregator package succeeding."


def test_go_test_passes():
    project_dir = "/home/user/aggregator"
    assert os.path.isdir(project_dir), f"Directory {project_dir} does not exist."

    result = subprocess.run(
        ["go", "test", "./..."],
        cwd=project_dir,
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"go test failed with return code {result.returncode}.\nStdout:\n{result.stdout}\nStderr:\n{result.stderr}"
TEST_EOF

if [ "$ok" -eq 1 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
