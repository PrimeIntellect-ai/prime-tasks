#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make g++
    pip3 install pytest grpcio grpcio-tools

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project/proto \
             /home/user/project/cpp \
             /home/user/project/python \
             /home/user/project/build

    cat << 'EOF' > /home/user/project/proto/metadata.proto
syntax = "proto3";
package metadata;

service MetadataService {
    rpc Process (ProcessRequest) returns (ProcessResponse);
}

message ProcessRequest {
    string client_id = 1;
    string data = 2;
}

message ProcessResponse {
    string result = 1;
}
EOF

    cat << 'EOF' > /home/user/project/cpp/processor.cpp
#include <cstring>
#include <cstdio>

extern "C" {
    void process_data(const char* input, char* output) {
        // BUG: buffer overflow if input is > 50 chars
        char temp[50];
        strcpy(temp, input); 
        sprintf(output, "Processed: %s", temp);
    }
}
EOF

    cat << 'EOF' > /home/user/project/Makefile
# Incomplete Makefile
all:
	echo "Not implemented"
EOF

    cat << 'EOF' > /home/user/project/python/server.py
import grpc
from concurrent import futures
import time
import ctypes
import os

# STUB: Needs implementation

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    # server.add_insecure_port('[::]:50051')
    # server.start()
    # server.wait_for_termination()

if __name__ == '__main__':
    serve()
EOF

    chown -R user:user /home/user/project
    chmod -R 777 /home/user
