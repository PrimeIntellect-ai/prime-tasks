#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl wget build-essential protobuf-compiler
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

    # Install grpcurl
    wget https://github.com/fullstorydev/grpcurl/releases/download/v1.8.7/grpcurl_1.8.7_linux_x86_64.tar.gz
    tar -xvf grpcurl_1.8.7_linux_x86_64.tar.gz -C /usr/local/bin grpcurl
    rm grpcurl_1.8.7_linux_x86_64.tar.gz

    # Create directories
    mkdir -p /home/user/protos/1.0.0
    mkdir -p /home/user/protos/1.1.0
    mkdir -p /home/user/protos/2.0.0

    # Create proto files
    cat << 'EOF' > /home/user/protos/1.0.0/api.proto
syntax = "proto3";
package api;
service MobileApi {
    rpc Login (LoginReq) returns (LoginRes);
    rpc GetData (DataReq) returns (DataRes);
}
message LoginReq { string user = 1; }
message LoginRes { string token = 1; }
message DataReq { string token = 1; }
message DataRes { string data = 1; }
EOF

    cat << 'EOF' > /home/user/protos/1.1.0/api.proto
syntax = "proto3";
package api;
service MobileApi {
    rpc Login (LoginReq) returns (LoginRes);
    rpc GetData (DataReq) returns (DataRes);
    rpc Logout (LogoutReq) returns (LogoutRes);
}
message LoginReq { string user = 1; string pass = 2; }
message LoginRes { string token = 1; }
message DataReq { string token = 1; }
message DataRes { string data = 1; string extra = 2; }
message LogoutReq { string token = 1; }
message LogoutRes { bool success = 1; }
EOF

    cat << 'EOF' > /home/user/protos/2.0.0/api.proto
syntax = "proto3";
package api;
service MobileApi {
    rpc Authenticate (AuthReq) returns (AuthRes);
    rpc GetData (DataReq) returns (DataRes);
}
message AuthReq { string user = 1; string pass = 2; }
message AuthRes { string token = 1; }
message DataReq { string token = 1; }
message DataRes { string data = 1; string extra = 2; }
EOF

    useradd -m -s /bin/bash user || true

    # Move rust installation to user home
    mv /root/.cargo /home/user/.cargo
    mv /root/.rustup /home/user/.rustup

    chmod -R 777 /home/user
