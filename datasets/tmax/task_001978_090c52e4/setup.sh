#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create the protos directory
    mkdir -p /home/user/protos

    # Create api.proto
    cat << 'EOF' > /home/user/protos/api.proto
syntax = "proto3";

import "auth.proto";
import "models.proto";

message ApiResponse {
    bool success = 1;
    string message = 2;
}

message GetUserRequest {
    string id = 1;
}

service ApiService {
    rpc GetUser(GetUserRequest) returns (ApiResponse);
}
EOF

    # Create models.proto
    cat << 'EOF' > /home/user/protos/models.proto
syntax = "proto3";

import "api.proto";

message User {
    string id = 1;
    string name = 2;
    ApiResponse last_status = 3;
}
EOF

    # Create auth.proto
    cat << 'EOF' > /home/user/protos/auth.proto
syntax = "proto3";

import "models.proto";

message Token {
    string token = 1;
    User user = 2;
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
