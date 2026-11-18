#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest grpcio grpcio-tools redis

    mkdir -p /app/proto
    mkdir -p /app/tests

    cat << 'EOF' > /app/proto/expression.proto
syntax = "proto3";
package expression;

service ExpressionService {
  rpc Evaluate (ExpressionRequest) returns (ExpressionResponse);
}

message ExpressionRequest {
  string expr = 1;
}

message ExpressionResponse {
  bool result = 1;
}
EOF

    cat << 'EOF' > /app/eval_server.py
import grpc
from concurrent import futures
import time
import expression_pb2
import expression_pb2_grpc
import os

cache = {}

class ExpressionServiceServicer(expression_pb2_grpc.ExpressionServiceServicer):
    def Evaluate(self, request, context):
        expr = request.expr
        # Simulate memory-intensive AST caching
        cache[expr] = [expr] * 1000 
        try:
            res = eval(expr)
        except Exception:
            res = False
        return expression_pb2.ExpressionResponse(result=bool(res))

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    expression_pb2_grpc.add_ExpressionServiceServicer_to_server(ExpressionServiceServicer(), server)
    server.add_insecure_port('[::]:50051')
    server.start()
    server.wait_for_termination()

if __name__ == '__main__':
    serve()
EOF

    cat << 'EOF' > /app/load_tester.py
import grpc
import expression_pb2
import expression_pb2_grpc
import sys

def run():
    channel = grpc.insecure_channel('localhost:50051')
    stub = expression_pb2_grpc.ExpressionServiceStub(channel)
    for i in range(50000):
        try:
            response = stub.Evaluate(expression_pb2.ExpressionRequest(expr=f"{i} == {i}"))
            if not response.result:
                print("Incorrect result")
                sys.exit(1)
        except Exception as e:
            print("Error:", e)
            sys.exit(1)
    print("Load test complete.")

if __name__ == '__main__':
    run()
EOF

    cat << 'EOF' > /app/tests/test_fixtures.py
import pytest

def test_placeholder():
    assert True
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /app
    chmod -R 777 /home/user
