#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest grpcio grpcio-tools websockets

mkdir -p /home/user/release

cat << 'EOF' > /home/user/release/processor.c
// Recently updated to use double instead of int for better precision
double process_data(double input) {
    return input * 2.5;
}
EOF

cat << 'EOF' > /home/user/release/data.proto
syntax = "proto3";

package data;

service DataProcessor {
  rpc Process (DataRequest) returns (DataResponse) {}
}

message DataRequest {
  double value = 1;
}

message DataResponse {
  double result = 1;
}
EOF

cat << 'EOF' > /home/user/release/grpc_server.py
import grpc
from concurrent import futures
import ctypes
import os
import data_pb2
import data_pb2_grpc

# Load shared library
lib = ctypes.CDLL(os.path.abspath('./libprocessor.so'))

# BUG: ABI mismatch. The C library was updated to double, but these are still int
lib.process_data.argtypes = [ctypes.c_int]
lib.process_data.restype = ctypes.c_int

class DataProcessorServicer(data_pb2_grpc.DataProcessorServicer):
    def Process(self, request, context):
        # Call the C shared library
        res = lib.process_data(ctypes.c_double(request.value))
        return data_pb2.DataResponse(result=res)

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    data_pb2_grpc.add_DataProcessorServicer_to_server(DataProcessorServicer(), server)
    server.add_insecure_port('[::]:50051')
    server.start()
    server.wait_for_termination()

if __name__ == '__main__':
    serve()
EOF

cat << 'EOF' > /home/user/release/ws_server.py
import asyncio
import websockets

async def handler(websocket):
    async for message in websocket:
        with open('/home/user/deploy_log.txt', 'w') as f:
            f.write(message)
        break

async def main():
    async with websockets.serve(handler, "localhost", 8765):
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    asyncio.run(main())
EOF

cat << 'EOF' > /home/user/release/deploy_check.py
import asyncio
import grpc
import data_pb2
import data_pb2_grpc
import websockets

async def report_success(message):
    # TODO: Connect to ws://localhost:8765 and send the message
    pass

def run():
    # TODO: Connect to gRPC localhost:50051
    # TODO: Call Process with value 4.0
    # TODO: Format result as "SUCCESS: <result>" and call report_success
    pass

if __name__ == '__main__':
    run()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
