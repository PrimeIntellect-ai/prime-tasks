#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y \
    python3 python3-pip \
    rustc cargo cmake make g++ \
    libgrpc++-dev protobuf-compiler-grpc protobuf-compiler libprotobuf-dev

pip3 install pytest

mkdir -p /home/user/project/proto
mkdir -p /home/user/project/backend_rust/src
mkdir -p /home/user/project/client_cpp

cat << 'EOF' > /home/user/project/proto/feature.proto
syntax = "proto3";
package feature;
service FeatureService {
    rpc GetFeature (FeatureRequest) returns (FeatureResponse);
}
message FeatureRequest {
    string id = 1;
}
message FeatureResponse {
    string data = 1;
}
EOF

cat << 'EOF' > /home/user/project/backend_rust/Cargo.toml
[package]
name = "backend_rust"
version = "0.1.0"
edition = "2021"

[dependencies]
tonic = "0.9"
prost = "0.11"
tokio = { version = "1.0", features = ["macros", "rt-multi-thread"] }

[build-dependencies]
tonic-build = "0.9"
EOF

cat << 'EOF' > /home/user/project/backend_rust/build.rs
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::compile_protos("../proto/feature.proto")?;
    Ok(())
}
EOF

cat << 'EOF' > /home/user/project/backend_rust/src/main.rs
use tonic::{transport::Server, Request, Response, Status};
use feature::feature_service_server::{FeatureService, FeatureServiceServer};
use feature::{FeatureRequest, FeatureResponse};

pub mod feature {
    tonic::include_proto!("feature");
}

#[derive(Default)]
pub struct MyFeatureService {}

#[tonic::async_trait]
impl FeatureService for MyFeatureService {
    async fn get_feature(
        &self,
        request: Request<FeatureRequest>,
    ) -> Result<Response<FeatureResponse>, Status> {
        let req_id = request.into_inner().id;
        let response_data = format!("FeatureData-{}", req_id);

        // Deliberate borrow checker error
        let _moved = response_data;

        let reply = feature::FeatureResponse {
            data: response_data, // ERROR: use of moved value
        };
        Ok(Response::new(reply))
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = "127.0.0.1:50051".parse().unwrap();
    let service = MyFeatureService::default();
    Server::builder()
        .add_service(FeatureServiceServer::new(service))
        .serve(addr)
        .await?;
    Ok(())
}
EOF

cat << 'EOF' > /home/user/project/client_cpp/CMakeLists.txt
cmake_minimum_required(VERSION 3.15)
project(FeatureTest CXX)

set(CMAKE_CXX_STANDARD 17)

find_package(gRPC CONFIG REQUIRED)
find_package(Protobuf REQUIRED)

# Generate proto bindings
set(PROTO_FILE "${CMAKE_CURRENT_SOURCE_DIR}/../proto/feature.proto")
set(PROTO_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../proto")
set(PROTO_SRC "${CMAKE_CURRENT_BINARY_DIR}/feature.pb.cc")
set(PROTO_HDR "${CMAKE_CURRENT_BINARY_DIR}/feature.pb.h")
set(GRPC_SRC "${CMAKE_CURRENT_BINARY_DIR}/feature.grpc.pb.cc")
set(GRPC_HDR "${CMAKE_CURRENT_BINARY_DIR}/feature.grpc.pb.h")

add_custom_command(
    OUTPUT "${PROTO_SRC}" "${PROTO_HDR}" "${GRPC_SRC}" "${GRPC_HDR}"
    COMMAND protobuf::protoc
    ARGS --grpc_out="${CMAKE_CURRENT_BINARY_DIR}"
         --cpp_out="${CMAKE_CURRENT_BINARY_DIR}"
         --plugin=protoc-gen-grpc=/usr/bin/grpc_cpp_plugin
         -I "${PROTO_DIR}"
         "${PROTO_FILE}"
    DEPENDS "${PROTO_FILE}"
)

add_executable(feature_test main.cpp ${PROTO_SRC} ${GRPC_SRC})
target_include_directories(feature_test PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
EOF

cat << 'EOF' > /home/user/project/client_cpp/main.cpp
#include <iostream>
#include <memory>
#include <string>
#include <grpcpp/grpcpp.h>
#include "feature.grpc.pb.h"

using grpc::Channel;
using grpc::ClientContext;
using grpc::Status;
using feature::FeatureService;
using feature::FeatureRequest;
using feature::FeatureResponse;

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <id>" << std::endl;
        return 1;
    }

    std::string id(argv[1]);
    auto channel = grpc::CreateChannel("localhost:50051", grpc::InsecureChannelCredentials());
    std::unique_ptr<FeatureService::Stub> stub = FeatureService::NewStub(channel);

    FeatureRequest request;
    request.set_id(id);
    FeatureResponse response;
    ClientContext context;

    Status status = stub->GetFeature(&context, request, &response);
    if (status.ok()) {
        std::cout << response.data() << std::endl;
        return 0;
    } else {
        std::cerr << status.error_code() << ": " << status.error_message() << std::endl;
        return 1;
    }
}
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
