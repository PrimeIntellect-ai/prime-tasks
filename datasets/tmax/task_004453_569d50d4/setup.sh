#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest grpcio grpcio-tools packaging websockets

mkdir -p /home/user/project
cd /home/user/project

cat << 'EOF' > /home/user/project/service.proto
syntax = "proto3";

package proxy;

service ProxyService {
  rpc SendMessage (MessageRequest) returns (MessageResponse) {}
}

message MessageRequest {
  string content = 1;
  string client_version = 2;
}

message MessageResponse {
  bool success = 1;
}
EOF

cat << 'EOF' > /home/user/project/ws_server.py
import time
from concurrent import futures
import grpc
import service_pb2
import service_pb2_grpc

MIN_VERSION = "2.2.0"

class ProxyServiceServicer(service_pb2_grpc.ProxyServiceServicer):
    def SendMessage(self, request, context):
        with open("/home/user/project/proxy_results.log", "a") as f:
            # BUG: Naive string comparison for semantic versions
            if request.client_version >= MIN_VERSION:
                f.write("SUCCESS: Forwarded message to WS\n")
                return service_pb2.MessageResponse(success=True)
            else:
                f.write("REJECTED: Version too low\n")
                return service_pb2.MessageResponse(success=False)

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    service_pb2_grpc.add_ProxyServiceServicer_to_server(ProxyServiceServicer(), server)
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

cat << 'EOF' > /home/user/project/test_client.py
import grpc
import service_pb2
import service_pb2_grpc

def run():
    with grpc.insecure_channel('localhost:50051') as channel:
        stub = service_pb2_grpc.ProxyServiceStub(channel)

        # Test 1: Should be rejected
        stub.SendMessage(service_pb2.MessageRequest(content="hello", client_version="2.1.0"))

        # Test 2: Should be accepted (string "2.10.0" < "2.2.0" in Python, which is the bug being tested)
        stub.SendMessage(service_pb2.MessageRequest(content="world", client_version="2.10.0"))

if __name__ == '__main__':
    run()
EOF

touch /home/user/project/proxy_results.log

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
