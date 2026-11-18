#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        cmake \
        valgrind \
        g++ \
        protobuf-compiler-grpc \
        libgrpc++-dev \
        libprotobuf-dev \
        protobuf-compiler \
        pkg-config \
        cargo \
        rustc

    pip3 install pytest

    # Create project structure
    mkdir -p /home/user/polyglot_calc/proto
    mkdir -p /home/user/polyglot_calc/cpp_server
    mkdir -p /home/user/polyglot_calc/rust_client/src

    # Create proto file
    cat << 'EOF' > /home/user/polyglot_calc/proto/calc.proto
syntax = "proto3";
package calc;
service Calculator {
  rpc Evaluate (EvalRequest) returns (EvalResponse) {}
}
message EvalRequest {
  string expression = 1;
}
message EvalResponse {
  int32 result = 1;
}
EOF

    # Create C++ CMakeLists.txt
    cat << 'EOF' > /home/user/polyglot_calc/cpp_server/CMakeLists.txt
cmake_minimum_required(VERSION 3.15)
project(calc_server CXX)
set(CMAKE_CXX_STANDARD 17)
find_package(gRPC CONFIG REQUIRED)
find_package(Protobuf REQUIRED)
# Missing protobuf generation and link commands (Intentional bug)
# Expected fix: add protoc generation and link gRPC::grpc++ Protobuf::libprotobuf

add_executable(calc_server main.cc evaluator.cc)
EOF

    # Create C++ evaluator.h
    cat << 'EOF' > /home/user/polyglot_calc/cpp_server/evaluator.h
#ifndef EVALUATOR_H
#define EVALUATOR_H
#include <string>
int evaluate_rpn(const std::string& expr);
#endif
EOF

    # Create C++ evaluator.cc
    cat << 'EOF' > /home/user/polyglot_calc/cpp_server/evaluator.cc
#include "evaluator.h"
#include <string>
#include <stack>
#include <sstream>

int evaluate_rpn(const std::string& expr) {
    std::stack<int*> s;
    std::stringstream ss(expr);
    std::string token;
    while (ss >> token) {
        if (token == "+" || token == "*") {
            int* b = s.top(); s.pop();
            int* a = s.top(); s.pop();
            int* res = new int;
            if (token == "+") *res = *a + *b;
            if (token == "*") *res = *a + *b; // Logic bug here (should be *)
            s.push(res);
            // Memory leak: a and b are not deleted
        } else {
            int* val = new int(std::stoi(token));
            s.push(val);
        }
    }
    int result = *s.top();
    // Memory leak: s.top() is not deleted
    return result;
}
EOF

    # Create C++ main.cc
    cat << 'EOF' > /home/user/polyglot_calc/cpp_server/main.cc
#include <iostream>
#include <memory>
#include <string>
#include <grpcpp/grpcpp.h>
#include "calc.grpc.pb.h"
#include "evaluator.h"

using grpc::Server;
using grpc::ServerBuilder;
using grpc::ServerContext;
using grpc::Status;
using calc::Calculator;
using calc::EvalRequest;
using calc::EvalResponse;

class CalculatorServiceImpl final : public Calculator::Service {
  Status Evaluate(ServerContext* context, const EvalRequest* request,
                  EvalResponse* reply) override {
    int result = evaluate_rpn(request->expression());
    reply->set_result(result);
    return Status::OK;
  }
};

void RunServer() {
  std::string server_address("0.0.0.0:50051");
  CalculatorServiceImpl service;

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

    # Create Rust Cargo.toml
    cat << 'EOF' > /home/user/polyglot_calc/rust_client/Cargo.toml
[package]
name = "rust_client"
version = "0.1.0"
edition = "2021"

[dependencies]
tonic = "0.8"
prost = "0.11"
tokio = { version = "1.0", features = ["macros", "rt-multi-thread"] }

[build-dependencies]
tonic-build = "0.8"
EOF

    # Create Rust build.rs
    cat << 'EOF' > /home/user/polyglot_calc/rust_client/build.rs
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::compile_protos("../proto/calc.proto")?;
    Ok(())
}
EOF

    # Create Rust main.rs
    cat << 'EOF' > /home/user/polyglot_calc/rust_client/src/main.rs
pub mod calc {
    tonic::include_proto!("calc");
}

use calc::calculator_client::CalculatorClient;
use calc::EvalRequest;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut client = CalculatorClient::connect("http://127.0.0.1:50051").await?;

    let request = tonic::Request::new(EvalRequest {
        expression: "3 4 + 5 *".into(),
    });

    let response = client.evaluate(request).await?;

    println!("{}", response.into_inner().result);

    Ok(())
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
