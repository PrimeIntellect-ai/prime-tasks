#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest grpcio grpcio-tools websockets packaging semantic_version

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/extractor.c
#include <string.h>
#include <stdlib.h>

// Bug: buffer overflow if input string > 15 chars
void extract_metadata(const char* input, char* output) {
    char buffer[16];
    // The agent must change this to strncpy(buffer, input, 15); buffer[15] = '\0';
    strcpy(buffer, input); 
    strcpy(output, buffer);
}
EOF

    cat << 'EOF' > /home/user/build_service.proto
syntax = "proto3";
package build;

service PipelineTester {
    rpc ValidateRelease (ReleaseRequest) returns (ReleaseReply) {}
}

message ReleaseRequest {
    string version_payload = 1;
}

message ReleaseReply {
    string validation_code = 1;
}
EOF

    cat << 'EOF' > /home/user/grpc_server.py
import grpc
from concurrent import futures
import time
import ctypes
import os
import json

import build_service_pb2
import build_service_pb2_grpc

class PipelineTesterServicer(build_service_pb2_grpc.PipelineTesterServicer):
    def __init__(self):
        self.lib = ctypes.CDLL(os.path.abspath('libextractor.so'))
        self.lib.extract_metadata.argtypes = [ctypes.c_char_p, ctypes.c_char_p]

    def ValidateRelease(self, request, context):
        in_buf = request.version_payload.encode('utf-8')
        out_buf = ctypes.create_string_buffer(32)
        # This will crash if in_buf is long and the C library isn't fixed
        self.lib.extract_metadata(in_buf, out_buf)

        extracted = out_buf.value.decode('utf-8')
        # Secret code based on the expected highest stable version (2.0.1)
        if extracted == "2.0.1":
            return build_service_pb2.ReleaseReply(validation_code="SUCCESS_201_METADATA_OK")
        else:
            return build_service_pb2.ReleaseReply(validation_code="FAIL_INVALID_VERSION")

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    build_service_pb2_grpc.add_PipelineTesterServicer_to_server(PipelineTesterServicer(), server)
    server.add_insecure_port('[::]:50051')
    server.start()
    try:
        while True:
            time.sleep(86400)
    except KeyboardInterrupt:
        server.stop(0)

if __name__ == '__main__':
    serve()
EOF

    cat << 'EOF' > /home/user/ws_server.py
import asyncio
import websockets
import json

async def handler(websocket, path):
    payload = json.dumps({"candidates": ["1.0.0", "2.1.0-alpha", "1.5.2", "2.0.1", "1.5.11"]})
    await websocket.send(payload)
    # keep connection open a bit just in case
    await asyncio.sleep(10)

start_server = websockets.serve(handler, "localhost", 8080)

asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

    cat << 'EOF' > /home/user/start_services.sh
#!/bin/bash
python3 /home/user/ws_server.py &
EOF
    chmod +x /home/user/start_services.sh

    cd /home/user
    python3 -m grpc_tools.protoc -I. --python_out=. --grpc_python_out=. build_service.proto

    chmod -R 777 /home/user
