#!/bin/bash
set -u
mkdir -p /logs/verifier

VERIFY_TEST_FILE=""
cleanup() {
    if [ -n "$VERIFY_TEST_FILE" ]; then
        rm -f "$VERIFY_TEST_FILE"
    fi
}
trap cleanup EXIT

verify() {
    cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import re


def test_worker_c_fixed():
    filepath = "/home/user/polybuild/c_src/worker.c"
    assert os.path.isfile(filepath), f"File {filepath} is missing"
    with open(filepath, "r") as f:
        content = f.read()

    assert "i <= 5" not in content, "worker.c still contains the out-of-bounds loop condition 'i <= 5'"
    assert re.search(r'i\s*<\s*5', content) or re.search(r'i\s*<=\s*4', content), "worker.c does not contain the corrected loop condition (e.g., 'i < 5')"


def test_test_results_log():
    filepath = "/home/user/test_results.log"
    assert os.path.isfile(filepath), f"File {filepath} is missing. Did you run the tests and redirect the output?"
    with open(filepath, "r") as f:
        content = f.read()

    assert "PASS" in content, "test_results.log does not contain 'PASS'. The Go tests may have failed or not run correctly."


def test_go_mod_exists_and_requires_websocket():
    filepath = "/home/user/polybuild/go_src/go.mod"
    assert os.path.isfile(filepath), f"File {filepath} is missing. Did you initialize the Go module?"
    with open(filepath, "r") as f:
        content = f.read()

    assert "github.com/gorilla/websocket" in content, "go.mod does not require github.com/gorilla/websocket"


def test_builder_test_go_implementation():
    filepath = "/home/user/polybuild/go_src/builder_test.go"
    assert os.path.isfile(filepath), f"File {filepath} is missing"
    with open(filepath, "r") as f:
        content = f.read()

    assert "httptest.NewServer" in content, "builder_test.go does not contain httptest.NewServer to mock the server"
    assert "Upgrade" in content or "Upgrader" in content, "builder_test.go does not appear to upgrade the HTTP connection to a WebSocket"


def test_builder_uses_requested_concurrency_primitives():
    filepath = "/home/user/polybuild/go_src/builder.go"
    assert os.path.isfile(filepath), f"File {filepath} is missing"
    with open(filepath, "r") as f:
        content = f.read()

    assert re.search(r'\bgo\s+(?:func\s*\(|[A-Za-z_])', content), "builder.go does not start a goroutine"
    assert re.search(r'\bchan\b', content), "builder.go does not use a Go channel"
PY_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    rm -f /tmp/polybuild_worker_verify
    gcc -fsanitize=address,undefined -fno-omit-frame-pointer \
        /home/user/polybuild/c_src/worker.c -o /tmp/polybuild_worker_verify || return 1
    local c_output
    c_output=$(ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 /tmp/polybuild_worker_verify 2>&1) || {
        printf '%s\n' "$c_output"
        return 1
    }
    printf '%s\n' "$c_output" | grep -F "Worker initialized" >/dev/null || return 1

    cd /home/user/polybuild/go_src || return 1

    if ! timeout 60s go test -count=1 -v > /tmp/polybuild_user_go_test.log 2>&1; then
        cat /tmp/polybuild_user_go_test.log
        return 1
    fi

    if ! timeout 30s go test -list '^TestStreamBuild$' 2>/tmp/polybuild_test_list.err | grep -x 'TestStreamBuild' >/dev/null; then
        cat /tmp/polybuild_test_list.err
        echo "builder_test.go does not define TestStreamBuild"
        return 1
    fi

    VERIFY_TEST_FILE=$(mktemp /home/user/polybuild/go_src/verifier_behavior_XXXXXX_test.go)
    cat << 'GO_EOF' > "$VERIFY_TEST_FILE"
package main

import (
    "fmt"
    "net/http/httptest"
    "strings"
    "testing"
    "time"

    "github.com/gorilla/websocket"
)

func TestVerifierStreamBuildBehavior(t *testing.T) {
    upgrader := websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}
    serverConnections := make(chan *websocket.Conn, 1)
    releaseHandler := make(chan struct{})

    server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        conn, err := upgrader.Upgrade(w, r, nil)
        if err != nil {
            return
        }
        serverConnections <- conn
        <-releaseHandler
    }))
    defer server.Close()
    defer close(releaseHandler)

    wsURL := "ws" + strings.TrimPrefix(server.URL, "http")
    clientConn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
    if err != nil {
        t.Fatalf("dial websocket: %v", err)
    }
    defer clientConn.Close()

    var serverConn *websocket.Conn
    select {
    case serverConn = <-serverConnections:
    case <-time.After(2 * time.Second):
        t.Fatal("server did not receive websocket connection")
    }
    defer serverConn.Close()

    messages := make(chan string, 4)
    readErrors := make(chan error, 1)
    go func() {
        for {
            messageType, payload, err := serverConn.ReadMessage()
            if err != nil {
                readErrors <- err
                return
            }
            if messageType != websocket.TextMessage {
                readErrors <- fmt.Errorf("message type %d is not TextMessage", messageType)
                return
            }
            messages <- string(payload)
        }
    }()

    nonce := time.Now().UnixNano()
    first := fmt.Sprintf("verifier-first-%d", nonce)
    second := fmt.Sprintf("verifier-second-%d", nonce)
    command := fmt.Sprintf("printf '%s\\n'; sleep 2; printf '%s\\n'", first, second)

    streamDone := make(chan error, 1)
    go func() {
        streamDone <- StreamBuild(clientConn, command)
    }()

    select {
    case got := <-messages:
        if got != first {
            t.Fatalf("first streamed line = %q, want %q", got, first)
        }
    case err := <-readErrors:
        t.Fatalf("websocket read failed before first line: %v", err)
    case err := <-streamDone:
        t.Fatalf("StreamBuild returned before delayed command completed (error %v)", err)
    case <-time.After(1200 * time.Millisecond):
        t.Fatal("first output line was not streamed while the command was still running")
    }

    select {
    case err := <-streamDone:
        t.Fatalf("StreamBuild returned before the command produced its second line (error %v)", err)
    case <-time.After(500 * time.Millisecond):
    }

    select {
    case got := <-messages:
        if got != second {
            t.Fatalf("second streamed line = %q, want %q", got, second)
        }
    case err := <-readErrors:
        t.Fatalf("websocket read failed before second line: %v", err)
    case <-time.After(3 * time.Second):
        t.Fatal("second output line was not streamed")
    }

    select {
    case err := <-streamDone:
        if err != nil {
            t.Fatalf("StreamBuild returned an error for a successful command: %v", err)
        }
    case <-time.After(2 * time.Second):
        t.Fatal("StreamBuild did not return after sending all command output")
    }
}
GO_EOF

    # Add the net/http import required by the verifier-generated behavioral test.
    python3 - "$VERIFY_TEST_FILE" << 'PY_IMPORT_EOF'
import pathlib
import sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
s = s.replace('"fmt"\n', '"fmt"\n    "net/http"\n', 1)
p.write_text(s)
PY_IMPORT_EOF

    if ! timeout 60s go test -count=1 -run '^TestVerifierStreamBuildBehavior$' -v > /tmp/polybuild_behavior_test.log 2>&1; then
        cat /tmp/polybuild_behavior_test.log
        return 1
    fi
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
