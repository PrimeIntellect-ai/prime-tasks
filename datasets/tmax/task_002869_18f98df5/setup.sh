#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest grpcio grpcio-tools z3-solver

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/polyglot_service

    cat << 'EOF' > /home/user/polyglot_service/math_ops.proto
syntax = "proto3";

package math_ops;

service MagicService {
  rpc ComputeMagic (MagicRequest) returns (MagicResponse) {}
}

message MagicRequest {
  int32 x = 1;
  int32 y = 2;
}

message MagicResponse {
  int32 result = 1;
}
EOF

    cat << 'EOF' > /home/user/polyglot_service/libmath.c
#include <stdlib.h>

int calculate_magic(int x, int y) {
    // Artificial memory leak
    int* temp_array = (int*)malloc(100 * sizeof(int));
    for(int i=0; i<100; i++) {
        temp_array[i] = x * y;
    }
    int res = temp_array[50];
    // MISSING: deallocate temp_array;
    return res;
}
EOF

    cat << 'EOF' > /home/user/polyglot_service/server.py
import grpc
from concurrent import futures
import json
import ctypes
import os

import math_ops_pb2
import math_ops_pb2_grpc

class MagicServiceServicer(math_ops_pb2_grpc.MagicServiceServicer):
    def __init__(self):
        self.lib = ctypes.CDLL(os.path.join(os.path.dirname(__file__), 'libmath.so'))
        self.lib.calculate_magic.argtypes = [ctypes.c_int, ctypes.c_int]
        self.lib.calculate_magic.restype = ctypes.c_int

    def ComputeMagic(self, request, context):
        res = self.lib.calculate_magic(request.x, request.y)

        with open('/home/user/result.json', 'w') as f:
            json.dump({"x": request.x, "y": request.y, "result": res}, f)

        return math_ops_pb2.MagicResponse(result=res)

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    math_ops_pb2_grpc.add_MagicServiceServicer_to_server(MagicServiceServicer(), server)
    server.add_insecure_port('[::]:50051')
    server.start()
    server.wait_for_termination()

if __name__ == '__main__':
    serve()
EOF

    chmod -R 777 /home/user
