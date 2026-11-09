#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server cmake build-essential gcc wget protobuf-compiler
pip3 install pytest flask grpcio grpcio-tools redis

# Install Go 1.23 to satisfy new protobuf module requirements
wget https://go.dev/dl/go1.23.0.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.23.0.linux-amd64.tar.gz
rm go1.23.0.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

# Install protoc-gen-go and protoc-gen-go-grpc
GOPATH=/usr/local/go go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
GOPATH=/usr/local/go go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

mkdir -p /home/user/app/c_src
mkdir -p /home/user/app/proto
mkdir -p /home/user/app/python_gateway
mkdir -p /home/user/app/go_src

# Create CMakeLists.txt
cat << 'EOF' > /home/user/app/c_src/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(processor C)
add_library(processor SHARED processor.c)
EOF

# Create processor.c
cat << 'EOF' > /home/user/app/c_src/processor.c
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

char* process_data(const char* input) {
    char* output = malloc(strlen(input) + 11);
    sprintf(output, "PROCESSED:%s", input);
    return output;
}
EOF

# Create processor.proto
cat << 'EOF' > /home/user/app/proto/processor.proto
syntax = "proto3";
package processor;
option go_package = "./pb";

service ProcessorService {
    rpc Process (ProcessRequest) returns (ProcessResponse);
}

message ProcessRequest {
    string client_id = 1;
    string input_data = 2;
}

message ProcessResponse {
    string output_data = 1;
}
EOF

# Generate Python gRPC code
python3 -m grpc_tools.protoc -I/home/user/app/proto --python_out=/home/user/app/python_gateway --grpc_python_out=/home/user/app/python_gateway /home/user/app/proto/processor.proto

# Create python_gateway/app.py
cat << 'EOF' > /home/user/app/python_gateway/app.py
import flask
from flask import request, jsonify
import grpc
import processor_pb2
import processor_pb2_grpc

app = flask.Flask(__name__)

@app.route('/process', methods=['POST'])
def process():
    data = request.json
    client_id = data.get("client_id", "")
    input_data = data.get("input_data", "")

    try:
        channel = grpc.insecure_channel('127.0.0.1:50051')
        stub = processor_pb2_grpc.ProcessorServiceStub(channel)
        req = processor_pb2.ProcessRequest(client_id=client_id, input_data=input_data)
        resp = stub.Process(req)
        return jsonify({"output_data": resp.output_data}), 200
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.RESOURCE_EXHAUSTED:
            return jsonify({"error": "Rate limit exceeded"}), 429
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

# Create go_src/main.go
cat << 'EOF' > /home/user/app/go_src/main.go
package main

func main() {
}
EOF

# Create start.sh
cat << 'EOF' > /home/user/app/start.sh
#!/bin/bash
EOF
chmod +x /home/user/app/start.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
