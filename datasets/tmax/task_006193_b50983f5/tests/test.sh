#!/bin/bash
set -u
mkdir -p /logs/verifier
export PATH="/usr/local/go/bin:/home/user/go/bin:$PATH"

WORKSPACE_DIR=/home/user/deploy-manager
HIDDEN_TEST="$WORKSPACE_DIR/zz_verifier_behavior_test.go"
cleanup() {
    rm -f "$HIDDEN_TEST"
}
trap cleanup EXIT

verify() {
    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

WORKSPACE_DIR = "/home/user/deploy-manager"

def test_go_mod_exists():
    go_mod_path = os.path.join(WORKSPACE_DIR, "go.mod")
    assert os.path.isfile(go_mod_path), f"Expected {go_mod_path} to exist."
    with open(go_mod_path, "r") as f:
        content = f.read()
    assert "module deploy-manager" in content, "go.mod does not contain the expected module name 'deploy-manager'."

def test_grpc_code_generated():
    pb_go_path = os.path.join(WORKSPACE_DIR, "pb", "rollout.pb.go")
    grpc_go_path = os.path.join(WORKSPACE_DIR, "pb", "rollout_grpc.pb.go")
    assert os.path.isfile(pb_go_path), f"Expected generated protobuf code at {pb_go_path} to exist."
    assert os.path.isfile(grpc_go_path), f"Expected generated gRPC code at {grpc_go_path} to exist."

def test_server_go_exists():
    server_go_path = os.path.join(WORKSPACE_DIR, "server.go")
    assert os.path.isfile(server_go_path), f"Expected {server_go_path} to exist."

def test_test_results_log_exists_and_passed():
    log_path = os.path.join(WORKSPACE_DIR, "test_results.log")
    assert os.path.isfile(log_path), f"Expected test results log at {log_path} to exist."

    with open(log_path, "r") as f:
        content = f.read()

    assert "PASS" in content, "The test results log does not contain 'PASS', indicating the tests did not pass successfully."
    assert "TestRolloutService" in content, "The test results log does not appear to contain the output of the TestRolloutService."
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    rm -f "$HIDDEN_TEST"
    cat << 'GO_EOF' > "$HIDDEN_TEST"
package main

import (
    "context"
    "net"
    "os"
    "path/filepath"
    "testing"
    "time"

    "deploy-manager/pb"
    "google.golang.org/grpc"
    "google.golang.org/grpc/credentials/insecure"
    "google.golang.org/grpc/test/bufconn"
)

func TestVerifierBehavior(t *testing.T) {
    rulesPath := filepath.Join(t.TempDir(), "dynamic-rules.txt")
    rules := "START,alpha,FIRST\nFIRST,beta,SECOND\nSECOND,gamma,THIRD\nFIRST,deny,REJECTED\nTHIRD,again,THIRD\n"
    if err := os.WriteFile(rulesPath, []byte(rules), 0600); err != nil {
        t.Fatalf("write dynamic rules: %v", err)
    }

    implementation, err := NewRolloutServer(rulesPath)
    if err != nil {
        t.Fatalf("NewRolloutServer failed: %v", err)
    }
    // The rules must have been read during initialization, not deferred until RPCs.
    if err := os.Remove(rulesPath); err != nil {
        t.Fatalf("remove dynamic rules after initialization: %v", err)
    }

    listener := bufconn.Listen(1024 * 1024)
    grpcServer := grpc.NewServer()
    pb.RegisterRolloutServiceServer(grpcServer, implementation)
    go func() { _ = grpcServer.Serve(listener) }()
    defer grpcServer.Stop()

    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()
    conn, err := grpc.DialContext(ctx, "bufnet",
        grpc.WithContextDialer(func(context.Context, string) (net.Conn, error) {
            return listener.Dial()
        }),
        grpc.WithTransportCredentials(insecure.NewCredentials()),
        grpc.WithBlock(),
    )
    if err != nil {
        t.Fatalf("dial in-memory gRPC server: %v", err)
    }
    defer conn.Close()

    client := pb.NewRolloutServiceClient(conn)
    cases := []struct {
        sequence string
        expected string
    }{
        {"", "START"},
        {"alpha", "FIRST"},
        {"alpha,beta", "SECOND"},
        {"alpha,beta,gamma", "THIRD"},
        {"alpha,beta,gamma,again,again", "THIRD"},
        {"alpha,deny", "REJECTED"},
        {"unknown", "REJECTED"},
        {"alpha,unknown", "REJECTED"},
        {"alpha,,beta", "SECOND"},
        {",alpha,beta,", "SECOND"},
    }

    for _, tc := range cases {
        response, err := client.EvaluateRollout(ctx, &pb.RolloutRequest{Sequence: tc.sequence})
        if err != nil {
            t.Errorf("EvaluateRollout(%q) returned error: %v", tc.sequence, err)
            continue
        }
        if response == nil || response.Tier != tc.expected {
            got := "<nil>"
            if response != nil {
                got = response.Tier
            }
            t.Errorf("EvaluateRollout(%q): expected %q, got %q", tc.sequence, tc.expected, got)
        }
    }
}
GO_EOF

    cd "$WORKSPACE_DIR" || return 1
    timeout 120s go test -count=1 -v ./... > /tmp/verifier_go_test.log 2>&1 || {
        cat /tmp/verifier_go_test.log
        return 1
    }
    cat /tmp/verifier_go_test.log
    grep -q -- '--- PASS: TestRolloutService' /tmp/verifier_go_test.log || return 1
    grep -q -- '--- PASS: TestVerifierBehavior' /tmp/verifier_go_test.log || return 1
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
