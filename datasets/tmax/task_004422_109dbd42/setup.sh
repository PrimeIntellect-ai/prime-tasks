#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest grpcio grpcio-tools

    mkdir -p /home/user/src

    cat << 'EOF' > /home/user/src/service.proto
syntax = "proto3";

service DataProcessor {
    rpc GetTokenDiff (DiffRequest) returns (DiffResponse);
}

message DiffRequest {
    string input_a = 1;
    string input_b = 2;
}

message DiffResponse {
    repeated string tokens = 1;
}
EOF

    cat << 'EOF' > /home/user/src/processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define MAX_TOKENS 5

// State machine to extract alphanumeric tokens
int extract_tokens(const char* input, char** out_tokens) {
    int state = 0;
    int token_count = 0;
    char buffer[256];
    int buf_idx = 0;

    for (int i = 0; i <= strlen(input); i++) {
        char c = input[i];
        if (state == 0) {
            if (isalnum(c)) {
                state = 1;
                buffer[buf_idx++] = c;
            }
        } else if (state == 1) {
            if (isalnum(c)) {
                buffer[buf_idx++] = c;
            } else {
                buffer[buf_idx] = '\0';
                // BUG: No bounds checking on token_count!
                out_tokens[token_count] = strdup(buffer);
                token_count++;
                buf_idx = 0;
                state = 0;
            }
        }
    }
    return token_count;
}

void free_tokens(char** tokens, int count) {
    for (int i = 0; i < count; i++) {
        free(tokens[i]);
    }
}
EOF

    cat << 'EOF' > /home/user/src/server.py
import grpc
from concurrent import futures
import ctypes
import os

# Generate proto bindings dynamically or assume they are compiled
import service_pb2
import service_pb2_grpc

# BUG: Hardcoded to wrong path
lib = ctypes.CDLL('/usr/lib/libprocessor.so')

class DataProcessorServicer(service_pb2_grpc.DataProcessorServicer):
    def GetTokenDiff(self, request, context):
        # TODO: Implement parsing, sorting, diffing
        pass

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    service_pb2_grpc.add_DataProcessorServicer_to_server(DataProcessorServicer(), server)
    server.add_insecure_port('[::]:50051')
    server.start()
    server.wait_for_termination()

if __name__ == '__main__':
    serve()
EOF

    cat << 'EOF' > /home/user/src/client.py
import grpc
import service_pb2
import service_pb2_grpc

def run():
    with grpc.insecure_channel('localhost:50051') as channel:
        stub = service_pb2_grpc.DataProcessorStub(channel)
        req = service_pb2.DiffRequest(
            input_a="alpha beta gamma delta epsilon zeta eta theta",
            input_b="alpha beta gamma omega epsilon zeta eta iota"
        )
        response = stub.GetTokenDiff(req)

        with open('/home/user/diff_result.txt', 'w') as f:
            for token in response.tokens:
                f.write(token + '\n')

if __name__ == '__main__':
    run()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
