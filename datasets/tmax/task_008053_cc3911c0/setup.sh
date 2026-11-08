#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/src/protos/v1
    mkdir -p /home/user/src/protos/v2

    # Create the initial v1 proto file
    cat << 'EOF' > /home/user/src/protos/v1/user.proto
syntax = "proto3";

package v1;

message User {
  int32 user_id = 1;
  string username = 2;
  int32 group_id = 3;
  bool is_active = 4;
  int32 age = 5;
}
EOF

    # Set permissions
    chown -R user:user /home/user/src
    chmod -R 777 /home/user
