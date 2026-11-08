#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/project/proto

    cat << 'EOF' > /home/user/project/proto/calc.proto
syntax = "proto3";
package calc;

service Calculator {
  rpc Evaluate (CalcRequest) returns (CalcResponse) {}
}

message CalcRequest {
  string client_id = 1;
  string b64_expression = 2;
}

message CalcResponse {
  double result = 1;
}
EOF

    cat << 'EOF' > /home/user/project/server.py
import grpc
from concurrent import futures
import base64
import time
import calc_pb2
import calc_pb2_grpc

class RateLimiter:
    def __init__(self):
        self.requests = 0
        self.start_time = time.time()

    def allow(self, client_id):
        # Broken: shared across all clients, doesn't reset correctly
        if time.time() - self.start_time > 1:
            self.requests = 0
            self.start_time = time.time()
        self.requests += 1
        return self.requests <= 5

limiter = RateLimiter()

class CalculatorServicer(calc_pb2_grpc.CalculatorServicer):
    def Evaluate(self, request, context):
        if not limiter.allow(request.client_id):
            context.abort(grpc.StatusCode.RESOURCE_EXHAUSTED, "Rate limit exceeded")

        # Vulnerable and fragile deserialization + evaluation
        expr = base64.b64decode(request.b64_expression).decode('utf-8')
        result = eval(expr)

        return calc_pb2.CalcResponse(result=float(result))

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    calc_pb2_grpc.add_CalculatorServicer_to_server(CalculatorServicer(), server)
    server.add_insecure_port('[::]:50051')
    server.start()
    server.wait_for_termination()

if __name__ == '__main__':
    serve()
EOF

    cat << 'EOF' > /home/user/project/requirements.txt
grpcio==1.59.0
grpcio-tools==1.59.0
protobuf==4.24.4
EOF

    pip3 install -r /home/user/project/requirements.txt

    cat << 'EOF' > /tmp/verify.py
import sys
import time
import grpc
import base64

sys.path.append('/home/user/project')
import calc_pb2
import calc_pb2_grpc

def test():
    channel = grpc.insecure_channel('localhost:50051')
    stub = calc_pb2_grpc.CalculatorStub(channel)

    def req(client_id, expr_str, expect_code=grpc.StatusCode.OK):
        b64 = base64.b64encode(expr_str.encode('utf-8')).decode('utf-8') if isinstance(expr_str, str) else expr_str
        try:
            resp = stub.Evaluate(calc_pb2.CalcRequest(client_id=client_id, b64_expression=b64))
            if expect_code != grpc.StatusCode.OK:
                print(f"Expected error {expect_code}, got OK")
                return False
            return True
        except grpc.RpcError as e:
            if e.code() != expect_code:
                print(f"Expected {expect_code}, got {e.code()}")
                return False
            return True

    print("Test 1: Normal expression")
    if not req("c1", "2 + 2 * 3"): return False

    print("Test 2: Invalid Base64")
    if not req("c2", "!!invalid_base64!!", grpc.StatusCode.INVALID_ARGUMENT): return False

    print("Test 3: RCE attempt (Invalid chars)")
    if not req("c3", "__import__('os').system('id')", grpc.StatusCode.INVALID_ARGUMENT): return False

    print("Test 4: Length limit")
    if not req("c4", "1" + " + 1"*30, grpc.StatusCode.INVALID_ARGUMENT): return False

    print("Test 5: Divide by zero")
    if not req("c5", "1 / 0", grpc.StatusCode.INVALID_ARGUMENT): return False

    print("Test 6: Rate limiting")
    # Send 5 valid requests
    for _ in range(5):
        if not req("c6", "1 + 1"): return False
    # 6th should fail with RESOURCE_EXHAUSTED
    if not req("c6", "1 + 1", grpc.StatusCode.RESOURCE_EXHAUSTED): return False

    # Wait 1.1s, should be allowed again
    time.sleep(1.1)
    if not req("c6", "1 + 1"): return False

    print("All tests passed.")
    return True

if __name__ == '__main__':
    if test():
        sys.exit(0)
    sys.exit(1)
EOF
    chmod +x /tmp/verify.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
