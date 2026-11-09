#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest grpcio grpcio-tools protobuf

    mkdir -p /home/user/protos

    cat << 'EOF' > /home/user/protos/base.proto
syntax = "proto3";
package myproject.base;

enum Status {
    UNKNOWN = 0;
    OK = 1;
    ERROR = 2;
}
EOF

    cat << 'EOF' > /home/user/protos/user.proto
syntax = "proto3";
package myproject.user;

import "base.proto";

message User {
    int32 id = 1;
    string name = 2;
    myproject.base.Status status = 3;
}
EOF

    cat << 'EOF' > /home/user/protos/service.proto
syntax = "proto3";
package myproject.service;

import "user.proto";

message UserResponse {
    myproject.user.User user = 1;
    string message = 2;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
