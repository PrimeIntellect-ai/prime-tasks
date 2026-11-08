#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv gcc libc6-dev
pip3 install pytest

mkdir -p /home/user/waf
cd /home/user/waf

cat << 'EOF' > matcher.c
#include <string.h>
int check_payload(const char* payload) {
    if (payload == NULL) return 0;
    if (strstr(payload, "<script>") != NULL) return 1;
    if (strstr(payload, "UNION SELECT") != NULL) return 1;
    return 0;
}
EOF

gcc -shared -o libmatcher.so -fPIC matcher.c

cat << 'EOF' > waf.proto
syntax = "proto3";

service WafService {
    rpc Inspect (InspectRequest) returns (InspectResponse) {}
}

message InspectRequest {
    string payload = 1;
}

message InspectResponse {
    bool is_malicious = 1;
}
EOF

cat << 'EOF' > server.py
import grpc
from concurrent import futures
import time
import ctypes
import waf_pb2
import waf_pb2_grpc

lib = ctypes.CDLL('./libmatcher.so')
lib.check_payload.argtypes = [ctypes.c_char_p]
lib.check_payload.restype = ctypes.c_int

class WafServicer(waf_pb2_grpc.WafServiceServicer):
    def Inspect(self, request, context):
        # BUG: in Py3, request.payload is a unicode string, but c_char_p expects bytes.
        # The agent must change this to request.payload.encode('utf-8')
        res = lib.check_payload(request.payload)
        return waf_pb2.InspectResponse(is_malicious=bool(res))

server = grpc.server(futures.ThreadPoolExecutor(max_workers=1))
waf_pb2_grpc.add_WafServiceServicer_to_server(WafServicer(), server)
server.add_insecure_port('[::]:50051')
server.start()
print "Server started"
while True:
    time.sleep(86400)
EOF

cat << 'EOF' > test_client.py
import grpc
import waf_pb2
import waf_pb2_grpc

def run():
    channel = grpc.insecure_channel('localhost:50051')
    stub = waf_pb2_grpc.WafServiceStub(channel)

    r1 = stub.Inspect(waf_pb2.InspectRequest(payload="hello world"))
    r2 = stub.Inspect(waf_pb2.InspectRequest(payload="<script>alert(1)</script>"))

    print("Clean: {}, Malicious: {}".format(r1.is_malicious, r2.is_malicious))

if __name__ == '__main__':
    run()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
