#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip protobuf-compiler
    pip3 install pytest

    mkdir -p /home/user/schemas /home/user/data

    cat << 'EOF' > /home/user/schemas/v1.proto
syntax = "proto3";
message TelemetryV1 {
  int32 device_id = 1;
  float temperature = 2;
  string status_code = 3;
}
EOF

    cat << 'EOF' > /home/user/schemas/v2.proto
syntax = "proto3";
message TelemetryV2 {
  int32 device_id = 1;
  float temperature = 2;
  enum Status {
    UNKNOWN = 0;
    OK = 1;
    ERROR = 2;
  }
  Status status = 3;
  int64 timestamp = 4;
}
EOF

    cat << 'EOF' > /home/user/data/input_v1.txt
device_id: 104
temperature: 42.5
status_code: "ERR"
EOF

    protoc --encode=TelemetryV1 -I/home/user/schemas /home/user/schemas/v1.proto < /home/user/data/input_v1.txt > /home/user/data/input_v1.bin
    rm /home/user/data/input_v1.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
