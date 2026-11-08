#!/bin/bash
set -u
mkdir -p /logs/verifier

WORKSPACE=/home/user/workspace
SERVER_BIN=/tmp/verified_patcher_server
SERVER_PID=""
TEST_FILE="$WORKSPACE/verifier_textbuffer_test.go"
CLIENT_FILE="$WORKSPACE/verifier_rpc_client.go"

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -f "$SERVER_BIN" "$TEST_FILE" "$CLIENT_FILE"
}
trap cleanup EXIT

run_checks() {
    cd "$WORKSPACE" || return 1

    # Preserve the original file assertions and additionally validate the
    # required protobuf schema.
    python3 - <<'PY' || return 1
import os
import re

proto_path = '/home/user/workspace/migration.proto'
server_path = '/home/user/workspace/server.go'
pb_go = '/home/user/workspace/migration/migration.pb.go'
grpc_go = '/home/user/workspace/migration/migration_grpc.pb.go'

assert os.path.isfile(proto_path), 'migration.proto is missing'
assert os.path.isfile(server_path), 'server.go is missing'
assert os.path.isfile(pb_go) or os.path.isfile(grpc_go), 'Generated protobuf Go files are missing in /home/user/workspace/migration/'

with open(proto_path, encoding='utf-8') as f:
    proto = f.read()

checks = [
    r'\bsyntax\s*=\s*["\']proto3["\']\s*;',
    r'\bpackage\s+migration\s*;',
    r'\boption\s+go_package\s*=\s*["\']\./migration["\']\s*;',
    r'\benum\s+Op\s*\{(?=[\s\S]*?\bKEEP\s*=\s*0\s*;)(?=[\s\S]*?\bADD\s*=\s*1\s*;)(?=[\s\S]*?\bDELETE\s*=\s*2\s*;)[\s\S]*?\}',
    r'\bmessage\s+Change\s*\{(?=[\s\S]*?\bOp\s+op\s*=\s*1\s*;)(?=[\s\S]*?\bstring\s+line\s*=\s*2\s*;)[\s\S]*?\}',
    r'\bmessage\s+PatchRequest\s*\{[\s\S]*?\brepeated\s+Change\s+changes\s*=\s*1\s*;[\s\S]*?\}',
    r'\bmessage\s+PatchResponse\s*\{[\s\S]*?\bstring\s+patched_code\s*=\s*1\s*;[\s\S]*?\}',
    r'\bservice\s+Patcher\s*\{[\s\S]*?\brpc\s+Apply\s*\(\s*PatchRequest\s*\)\s*returns\s*\(\s*PatchResponse\s*\)\s*;[\s\S]*?\}',
]
for pattern in checks:
    assert re.search(pattern, proto), 'migration.proto does not contain the required schema'
PY

    # Ensure the submitted proto is accepted by protoc.
    rm -rf /tmp/verifier_proto
    mkdir -p /tmp/verifier_proto
    protoc --proto_path="$WORKSPACE" --descriptor_set_out=/tmp/verifier_proto/migration.desc migration.proto || return 1

    # Compile and directly exercise the required TextBuffer implementation.
    cat > "$TEST_FILE" <<'GOEOF'
package main

import "testing"

func TestVerifierTextBuffer(t *testing.T) {
	var b TextBuffer
	if got := b.Render(); got != "" {
		t.Fatalf("empty Render() = %q, want empty string", got)
	}
	b.Append("first")
	b.Append("second")
	b.Append("")
	if got, want := b.Render(), "first\nsecond\n"; got != want {
		t.Fatalf("Render() = %q, want %q", got, want)
	}
}
GOEOF
    go test server.go "$TEST_FILE" || return 1
    rm -f "$TEST_FILE"

    # Building server.go verifies that its generated protobuf imports and gRPC
    # implementation compile together.
    go build -o "$SERVER_BIN" server.go || return 1

    "$SERVER_BIN" >/tmp/verified_patcher_server.log 2>&1 &
    SERVER_PID=$!

    # Wait for the submitted server to bind the required port. If another
    # process owns it, the submitted server will exit and this check fails.
    python3 - "$SERVER_PID" <<'PY' || return 1
import os
import socket
import sys
import time

pid = int(sys.argv[1])
for _ in range(100):
    try:
        os.kill(pid, 0)
    except OSError:
        raise AssertionError('submitted server exited before accepting connections')
    try:
        with socket.create_connection(('localhost', 50051), timeout=0.1):
            break
    except OSError:
        time.sleep(0.1)
else:
    raise AssertionError('submitted server did not listen on localhost:50051')
PY

    # Exercise the actual RPC with runtime-generated lines. The expected result
    # is independently derived from the operations sent in the request.
    cat > "$CLIENT_FILE" <<'GOEOF'
package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"strings"
	"time"

	pb "workspace/migration"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func randomLine(i int) string {
	buf := make([]byte, 12)
	if _, err := rand.Read(buf); err != nil {
		panic(err)
	}
	return fmt.Sprintf("runtime-%d-%s", i, hex.EncodeToString(buf))
}

func main() {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	conn, err := grpc.DialContext(ctx, "localhost:50051",
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithBlock())
	if err != nil {
		panic(err)
	}
	defer conn.Close()

	changes := make([]*pb.Change, 0, 24)
	wantLines := make([]string, 0, 16)
	ops := []pb.Op{pb.Op_KEEP, pb.Op_DELETE, pb.Op_ADD}
	for i := 0; i < 24; i++ {
		op := ops[i%len(ops)]
		line := randomLine(i)
		changes = append(changes, &pb.Change{Op: op, Line: line})
		if op == pb.Op_KEEP || op == pb.Op_ADD {
			wantLines = append(wantLines, line)
		}
	}

	response, err := pb.NewPatcherClient(conn).Apply(ctx, &pb.PatchRequest{Changes: changes})
	if err != nil {
		panic(err)
	}
	want := strings.Join(wantLines, "\n")
	if response.GetPatchedCode() != want {
		panic(fmt.Sprintf("Apply returned %q, want %q", response.GetPatchedCode(), want))
	}
}
GOEOF
    go run "$CLIENT_FILE" || return 1
    rm -f "$CLIENT_FILE"
    kill -0 "$SERVER_PID" 2>/dev/null || return 1

    # Remove any prewritten answer and require the provided client to obtain it
    # from the running submitted service.
    rm -f "$WORKSPACE/patched.py"
    go run client.go || return 1
    kill -0 "$SERVER_PID" 2>/dev/null || return 1

    # Preserve the original final output assertions exactly.
    cat > /tmp/test_final_state.py <<'PYTEST'
import os

def test_proto_file_exists():
    assert os.path.isfile('/home/user/workspace/migration.proto'), "migration.proto is missing"

def test_server_go_exists():
    assert os.path.isfile('/home/user/workspace/server.go'), "server.go is missing"

def test_proto_generated_files():
    pb_go = '/home/user/workspace/migration/migration.pb.go'
    grpc_go = '/home/user/workspace/migration/migration_grpc.pb.go'
    assert os.path.isfile(pb_go) or os.path.isfile(grpc_go), "Generated protobuf Go files are missing in /home/user/workspace/migration/"

def test_patched_py_content():
    patched_file = '/home/user/workspace/patched.py'
    assert os.path.isfile(patched_file), f"{patched_file} is missing"

    expected_content = (
        "from setuptools import setup\n"
        "print('Installing package...')\n"
        "setup(\n"
        "    name='mypkg',\n"
        "    version='1.0',\n"
        ")"
    )

    with open(patched_file, 'r') as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content.strip(), f"Content of {patched_file} does not match the expected patched output."
PYTEST
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
