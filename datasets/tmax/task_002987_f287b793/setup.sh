#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest grpcio grpcio-tools

    # Create directories
    mkdir -p /home/user/rust_auth/proto
    mkdir -p /home/user/rust_auth/src
    mkdir -p /app

    # Create proto file
    cat << 'EOF' > /home/user/rust_auth/proto/auth.proto
syntax = "proto3";

package auth;

service AuthService {
  rpc GenerateToken (GenerateTokenRequest) returns (GenerateTokenResponse) {}
}

message GenerateTokenRequest {
  string user_id = 1;
  string payload = 2;
}

message GenerateTokenResponse {
  string token = 1;
}
EOF

    # Create dummy broken Rust file
    cat << 'EOF' > /home/user/rust_auth/src/main.rs
fn main() {
    broken_code_here
}
EOF

    # Setup the hidden oracle in /app
    cp /home/user/rust_auth/proto/auth.proto /app/
    cd /app
    python3 -m grpc_tools.protoc -I. --python_out=. --grpc_python_out=. auth.proto

    cat << 'EOF' > /app/.hidden_oracle.py
import grpc
from concurrent import futures
import hmac
import hashlib
import time

import auth_pb2
import auth_pb2_grpc

class AuthService(auth_pb2_grpc.AuthServiceServicer):
    def GenerateToken(self, request, context):
        secret = b"WINTERMUTE_2049"
        msg = f"{request.user_id}|{request.payload}".encode('utf-8')
        token = hmac.new(secret, msg, hashlib.sha256).hexdigest()
        return auth_pb2.GenerateTokenResponse(token=token)

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    auth_pb2_grpc.add_AuthServiceServicer_to_server(AuthService(), server)
    server.add_insecure_port('127.0.0.1:50050')
    server.start()
    try:
        server.wait_for_termination()
    except KeyboardInterrupt:
        pass

if __name__ == '__main__':
    serve()
EOF

    # Create the C wrapper to act as the stripped binary oracle
    cat << 'EOF' > /app/oracle.c
#include <stdlib.h>

const char* secret = "WINTERMUTE_2049";

int main() {
    system("python3 /app/.hidden_oracle.py");
    return 0;
}
EOF

    gcc -O0 -o /app/legacy_auth /app/oracle.c
    strip /app/legacy_auth
    rm /app/oracle.c

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
