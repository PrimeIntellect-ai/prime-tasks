#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install task dependencies
    apt-get install -y protobuf-compiler protobuf-compiler-grpc libgrpc++-dev libprotobuf-dev build-essential
    pip3 install grpcio grpcio-tools

    # Create workspace
    mkdir -p /home/user/workspace

    # Create evaluator.h
    cat << 'EOF' > /home/user/workspace/evaluator.h
#ifndef EVALUATOR_H
#define EVALUATOR_H
#include <string>
#include <map>

struct EvalResult {
    int result;
    bool success;
    std::string error;
};

EvalResult evaluate_rpn(const std::string& expr, const std::map<std::string, int>& vars);

#endif
EOF

    # Create evaluator.cpp
    cat << 'EOF' > /home/user/workspace/evaluator.cpp
#include "evaluator.h"
#include <sstream>
#include <vector>
#include <iostream>

EvalResult evaluate_rpn(const std::string& expr, const std::map<std::string, int>& vars) {
    int stack[10]; // BUG: Fixed size stack, potential OOB, and no underflow check.
    int sp = 0;

    std::istringstream iss(expr);
    std::string token;

    while (iss >> token) {
        if (token == "+" || token == "-" || token == "*") {
            // BUG: No check for sp < 2 leading to undefined behavior/stack underflow
            int b = stack[--sp];
            int a = stack[--sp];
            if (token == "+") stack[sp++] = a + b;
            if (token == "-") stack[sp++] = a - b;
            if (token == "*") stack[sp++] = a * b;
        } else {
            // BUG: No check for sp >= 10 leading to buffer overflow
            if (vars.count(token)) {
                stack[sp++] = vars.at(token);
            } else {
                stack[sp++] = std::stoi(token);
            }
        }
    }

    if (sp != 1) {
        return {0, false, "Invalid expression format"};
    }

    return {stack[0], true, ""};
}
EOF

    # Create server.cpp
    cat << 'EOF' > /home/user/workspace/server.cpp
#include <iostream>
#include <memory>
#include <string>
#include <grpcpp/grpcpp.h>
#include "evaluator.grpc.pb.h"
#include "evaluator.h"

using grpc::Server;
using grpc::ServerBuilder;
using grpc::ServerContext;
using grpc::Status;
using build_expr::Evaluator;
using build_expr::EvalRequest;
using build_expr::EvalResponse;

class EvaluatorServiceImpl final : public Evaluator::Service {
  Status Evaluate(ServerContext* context, const EvalRequest* request, EvalResponse* reply) override {
    std::map<std::string, int> vars(request->variables().begin(), request->variables().end());
    EvalResult res = evaluate_rpn(request->expression(), vars);

    reply->set_success(res.success);
    if (res.success) {
        reply->set_result(res.result);
    } else {
        reply->set_error_message(res.error);
    }
    return Status::OK;
  }
};

void RunServer() {
  std::string server_address("0.0.0.0:50051");
  EvaluatorServiceImpl service;

  ServerBuilder builder;
  builder.AddListeningPort(server_address, grpc::InsecureServerCredentials());
  builder.RegisterService(&service);
  std::unique_ptr<Server> server(builder.BuildAndStart());
  std::cout << "Server listening on " << server_address << std::endl;
  server->Wait();
}

int main(int argc, char** argv) {
  RunServer();
  return 0;
}
EOF

    # Create client.py
    cat << 'EOF' > /home/user/workspace/client.py
import grpc
import json
import sys
import evaluator_pb2
import evaluator_pb2_grpc

def run(input_file, output_file):
    with open(input_file, 'r') as f:
        cases = json.load(f)

    results = []
    with grpc.insecure_channel('localhost:50051') as channel:
        stub = evaluator_pb2_grpc.EvaluatorStub(channel)
        for case in cases:
            req = evaluator_pb2.EvalRequest(
                expression=case['expr'],
                variables=case['vars']
            )
            try:
                resp = stub.Evaluate(req)
                results.append({
                    "expr": case['expr'],
                    "success": resp.success,
                    "result": resp.result if resp.success else 0,
                    "error": resp.error_message if not resp.success else ""
                })
            except Exception as e:
                 results.append({"expr": case['expr'], "success": False, "error": "RPC FAILED"})

    with open(output_file, 'w') as f:
        for r in results:
            f.write(f"{r['expr']} | {r['success']} | {r['result']} | {r['error']}\n")

if __name__ == '__main__':
    run(sys.argv[1], sys.argv[2])
EOF

    # Create test_cases.json
    cat << 'EOF' > /home/user/workspace/test_cases.json
[
  {"expr": "ARCH_ARM64 1 +", "vars": {"ARCH_ARM64": 1}},
  {"expr": "1 2 + 3 *", "vars": {}},
  {"expr": "+", "vars": {}},
  {"expr": "1 1 1 1 1 1 1 1 1 1 1 1 + + + + + + + + + + +", "vars": {}}
]
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
