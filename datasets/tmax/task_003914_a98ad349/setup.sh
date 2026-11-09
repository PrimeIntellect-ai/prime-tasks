#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > service.proto
syntax = "proto3";
service DataService {
  rpc ProcessData (Request) returns (Response);
}
message Request { string payload = 1; }
message Response { int32 result = 1; }
EOF

    cat << 'EOF' > fast_parser.c
#include <string.h>
int parse_magic(const char* data) {
    if (data == NULL) return 0;
    return 42;
}
EOF

    cat << 'EOF' > Makefile
libfastparser.so: fast_parser.c
	gcc -o libfastparser.so fast_parser.c
EOF

    cat << 'EOF' > server.py
import ctypes
import os
import grpc
from concurrent import futures
import service_pb2
import service_pb2_grpc

lib_path = os.path.join(os.path.dirname(__file__), "libfastparser.so")
lib = ctypes.CDLL(lib_path)

class MyService(service_pb2_grpc.DataServiceServicer):
    def ProcessData(self, request, context):
        val = lib.parse_magic(request.payload.encode('utf-8'))
        return service_pb2.Response(result=val)

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=1))
    service_pb2_grpc.add_DataServiceServicer_to_server(MyService(), server)
    server.add_insecure_port('[::]:50051')
    server.start()
    return server
EOF

    cat << 'EOF' > test_server.py
import server
import time

if __name__ == '__main__':
    s = server.serve()
    print("SERVER_STARTED_SUCCESSFULLY")
    s.stop(0)
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/project
    chmod -R 777 /home/user
