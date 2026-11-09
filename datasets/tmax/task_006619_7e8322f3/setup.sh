#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest grpcio-tools

    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/workspace/schema.proto
syntax = "proto3";
package audit;

message TransactionLog {
    string id = 1;
    string user_agent = 2;
    string request_payload = 3;
    int32 status_code = 4;
    string response_payload = 5;
}
EOF

    cat << 'EOF' > /home/user/workspace/tokens.txt
sk-abc12345
sk-xyz98765
token-5555
secret-9999
EOF

    cat << 'EOF' > /home/user/workspace/payloads.jsonl
{"id": "1", "user_agent": "Mozilla sk-abc12345 client", "request_payload": "login token-5555", "status_code": 200, "response_payload": "ok"}
{"id": "2", "user_agent": "curl/7.68.0", "request_payload": "query data", "status_code": 403, "response_payload": "Missing secret-9999 or sk-xyz98765"}
{"id": "3", "user_agent": "PostmanRuntime/7.28", "request_payload": "auth token-5555 and sk-abc12345", "status_code": 200, "response_payload": "success"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
