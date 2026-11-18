#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest grpcio grpcio-tools websockets

    mkdir -p /home/user
    cat << 'EOF' > /home/user/monitor.proto
syntax = "proto3";

package monitor;

message LogMessage {
  string level = 1;
  string payload = 2;
}

message Empty {}

service PipelineMonitor {
  rpc BroadcastLog (LogMessage) returns (Empty) {}
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
