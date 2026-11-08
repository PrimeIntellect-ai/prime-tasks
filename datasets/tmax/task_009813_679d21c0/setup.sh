#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget protobuf-compiler
    pip3 install pytest grpcio grpcio-tools protobuf

    # Install Go 1.23 to satisfy protoc-gen-go requirements
    wget https://go.dev/dl/go1.23.4.linux-amd64.tar.gz
    rm -rf /usr/local/go && tar -C /usr/local -xzf go1.23.4.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin

    # Install protoc-gen-go and protoc-gen-go-grpc
    go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
    cp /root/go/bin/protoc-gen-go /usr/local/bin/
    cp /root/go/bin/protoc-gen-go-grpc /usr/local/bin/

    # Create the proto file
    mkdir -p /home/user/project/schema
    cat << 'EOF' > /home/user/project/schema/sensor.proto
syntax = "proto3";

package sensor;
option go_package = "github.com/example/sensor";

service SensorStreamer {
  rpc FetchData (SensorRequest) returns (stream SensorResponse);
}

message SensorRequest {
  string client_id = 1;
}

message SensorResponse {
  float value = 1;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
