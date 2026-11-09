#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip protobuf-compiler wget tar
    pip3 install pytest

    # Install Go 1.23+ to satisfy protobuf requirements
    wget https://go.dev/dl/go1.23.4.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.23.4.linux-amd64.tar.gz
    rm go1.23.4.linux-amd64.tar.gz
    export PATH=/usr/local/go/bin:$PATH

    export GOPATH=/home/user/go
    export PATH=$PATH:$GOPATH/bin
    go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

    mkdir -p /home/user/deploy-manager/pb
    cd /home/user/deploy-manager

    cat << 'EOF' > rules.txt
START,build,CI
CI,test,QA
QA,approve,STAGING
STAGING,verify,PROD
CI,fail,REJECTED
QA,reject,REJECTED
EOF

    cat << 'EOF' > legacy_parser.py
import sys

def evaluate(rules_file, sequence):
    transitions = {}
    with open(rules_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line: continue
            src, token, dst = line.split(',')
            if src not in transitions:
                transitions[src] = {}
            transitions[src][token] = dst

    current_state = "START"
    for token in sequence.split(','):
        if not token: continue
        if token in transitions.get(current_state, {}):
            current_state = transitions[current_state][token]
        else:
            return "REJECTED"

    return current_state

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python legacy_parser.py <rules_file> <sequence>")
        sys.exit(1)
    print(evaluate(sys.argv[1], sys.argv[2]))
EOF

    cat << 'EOF' > pb/rollout.proto
syntax = "proto3";
package rollout;
option go_package = "deploy-manager/pb;pb";

service RolloutService {
  rpc EvaluateRollout (RolloutRequest) returns (RolloutResponse);
}

message RolloutRequest {
  string sequence = 1; // comma-separated tokens
}

message RolloutResponse {
  string tier = 1;
}
EOF

    cat << 'EOF' > server_test.go
package main

import (
	"context"
	"net"
	"testing"
	"time"

	"deploy-manager/pb"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func TestRolloutService(t *testing.T) {
	// Start the server
	server := grpc.NewServer()
	rolloutServer, err := NewRolloutServer("rules.txt")
	if err != nil {
		t.Fatalf("Failed to create server: %v", err)
	}
	pb.RegisterRolloutServiceServer(server, rolloutServer)

	lis, err := net.Listen("tcp", ":50051")
	if err != nil {
		t.Fatalf("Failed to listen: %v", err)
	}
	go func() {
		if err := server.Serve(lis); err != nil {
			panic(err)
		}
	}()
	defer server.Stop()

	// Wait for server to start
	time.Sleep(100 * time.Millisecond)

	// Connect client
	conn, err := grpc.Dial("localhost:50051", grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		t.Fatalf("Failed to dial: %v", err)
	}
	defer conn.Close()

	client := pb.NewRolloutServiceClient(conn)

	tests := []struct {
		sequence string
		expected string
	}{
		{"build,test,approve", "STAGING"},
		{"build,test,approve,verify", "PROD"},
		{"build,fail", "REJECTED"},
		{"build,test,reject", "REJECTED"},
		{"build,invalid", "REJECTED"},
		{"", "START"},
	}

	for _, tc := range tests {
		req := &pb.RolloutRequest{Sequence: tc.sequence}
		resp, err := client.EvaluateRollout(context.Background(), req)
		if err != nil {
			t.Errorf("EvaluateRollout failed for %q: %v", tc.sequence, err)
			continue
		}
		if resp.Tier != tc.expected {
			t.Errorf("For sequence %q, expected %q, got %q", tc.sequence, tc.expected, resp.Tier)
		}
	}
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
