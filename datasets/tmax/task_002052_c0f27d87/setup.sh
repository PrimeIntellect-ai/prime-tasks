#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest grpcio grpcio-tools

    mkdir -p /home/user/math_service
    cd /home/user/math_service

    cat << 'EOF' > math_service.proto
syntax = "proto3";

service PostfixEvaluator {
  rpc Evaluate (EvaluateRequest) returns (EvaluateResponse);
}

message EvaluateRequest {
  string expression = 1;
}

message EvaluateResponse {
  double result = 1;
  string error = 2; // Non-empty if there was a parsing/evaluation error
}
EOF

    cat << 'EOF' > server.py
import grpc
from concurrent import futures
import math

import math_service_pb2
import math_service_pb2_grpc

class PostfixEvaluatorServicer(math_service_pb2_grpc.PostfixEvaluatorServicer):
    def Evaluate(self, request, context):
        try:
            tokens = request.expression.split()
            stack = []
            for token in tokens:
                if token in ('+', '-', '*', '/', '^'):
                    # BUG: Popping in wrong order for a correct postfix evaluator
                    a = stack.pop()
                    b = stack.pop()
                    if token == '+': stack.append(a + b)
                    elif token == '-': stack.append(a - b) # Bug: should be b - a
                    elif token == '*': stack.append(a * b)
                    elif token == '/': stack.append(a / b) # Bug: should be b / a
                    elif token == '^': stack.append(math.pow(a, b)) # Bug: should be b ** a
                else:
                    stack.append(float(token))

            if len(stack) != 1:
                return math_service_pb2.EvaluateResponse(error="Invalid expression format")

            return math_service_pb2.EvaluateResponse(result=stack[0])
        except Exception as e:
            return math_service_pb2.EvaluateResponse(error=str(e))

def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    math_service_pb2_grpc.add_PostfixEvaluatorServicer_to_server(PostfixEvaluatorServicer(), server)
    server.add_insecure_port('[::]:50051')
    server.start()
    server.wait_for_termination()

if __name__ == '__main__':
    serve()
EOF

    cat << 'EOF' > /home/user/test_data.json
[
  {"expression": "5 1 2 + 4 * + 3 -", "expected": 14.0},
  {"expression": "4 2 /", "expected": 2.0},
  {"expression": "2 3 ^", "expected": 8.0},
  {"expression": "5 !", "expected": 120.0},
  {"expression": "3 ! 4 +", "expected": 10.0},
  {"expression": "10 3 - 2 ^", "expected": 49.0},
  {"expression": "invalid expression + +", "expected": null}
]
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
