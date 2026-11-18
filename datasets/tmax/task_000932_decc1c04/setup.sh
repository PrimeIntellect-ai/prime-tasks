#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go protobuf-compiler curl
    pip3 install pytest

    mkdir -p /home/user/app/proto
    mkdir -p /home/user/app/auth
    mkdir -p /home/user/app/gateway
    mkdir -p /home/user/app/backend
    mkdir -p /opt/oracle

    # Create broken auth.proto
    cat << 'EOF' > /home/user/app/proto/auth.proto
syntax = "proto3";
package auth;
option go_package = "auth/pb";

service AuthService {
  rpc Check(CheckRequest) returns (CheckResponse);
}

message CheckRequest {
  string expression = 1;
  // Missing attributes field
}

message CheckResponse {
  bool allowed = 1;
}
EOF

    # Create broken go.mod
    cat << 'EOF' > /home/user/app/auth/go.mod
module auth

go 1.18

// Broken dependencies
EOF

    # Create broken parser.go
    cat << 'EOF' > /home/user/app/auth/parser.go
package main

func ParseAndEvaluate(expr string, attrs map[string]string) bool {
    // Buggy implementation
    return false
}
EOF

    # Create oracle evaluator (mock script)
    cat << 'EOF' > /opt/oracle/evaluator
#!/usr/bin/env python3
import sys
import json

if len(sys.argv) != 3:
    sys.exit(1)

expr = sys.argv[1]
attrs = json.loads(sys.argv[2])
# Mock oracle logic
print("true")
EOF
    chmod +x /opt/oracle/evaluator

    # Create start.sh
    cat << 'EOF' > /home/user/app/start.sh
#!/bin/bash
# Broken startup script
EOF
    chmod +x /home/user/app/start.sh

    # Create gateway config
    cat << 'EOF' > /home/user/app/gateway/config.yaml
# Broken config
auth_target: "localhost:9999"
backend_target: "localhost:8888"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
