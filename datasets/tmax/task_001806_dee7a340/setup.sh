#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        build-essential \
        cmake \
        valgrind \
        protobuf-compiler \
        protobuf-compiler-grpc \
        libgrpc++-dev \
        libprotobuf-dev

    pip3 install pytest grpcio grpcio-tools

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backend
    mkdir -p /home/user/client

    cat << 'EOF' > /home/user/backend/data_service.proto
syntax = "proto3";
package dataprocess;

service DataService {
  rpc ProcessData (DataPoint) returns (DataResult) {}
}

message DataPoint {
  int32 id = 1;
  double value = 2;
}

message DataResult {
  int32 id = 1;
  double processed_value = 2;
}
EOF

    cat << 'EOF' > /home/user/backend/server.cpp
#include <iostream>
#include <memory>
#include <string>
#include <grpcpp/grpcpp.h>
#include "data_service.grpc.pb.h"

using grpc::Server;
using grpc::ServerBuilder;
using grpc::ServerContext;
using grpc::Status;
using dataprocess::DataPoint;
using dataprocess::DataResult;
using dataprocess::DataService;

class DataServiceImpl final : public DataService::Service {
  Status ProcessData(ServerContext* context, const DataPoint* request, DataResult* reply) override {
    // Intentional memory leak
    int* leak = new int[100];
    leak[0] = 1;

    reply->set_id(request->id());
    reply->set_processed_value(request->value() * 2.0); // Needs update

    return Status::OK;
  }
};

void RunServer() {
  std::string server_address("0.0.0.0:50051");
  DataServiceImpl service;
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

    cat << 'EOF' > /home/user/backend/CMakeLists.txt
cmake_minimum_required(VERSION 3.8)
project(DataProcessServer)

set(CMAKE_CXX_STANDARD 17)

find_package(Protobuf REQUIRED)
find_package(gRPC REQUIRED)

set(PROTO_FILE "data_service.proto")

add_custom_command(
    OUTPUT data_service.pb.cc data_service.pb.h data_service.grpc.pb.cc data_service.grpc.pb.h
    COMMAND protoc --cpp_out=. --grpc_out=. --plugin=protoc-gen-grpc=`which grpc_cpp_plugin` ${PROTO_FILE}
    DEPENDS ${PROTO_FILE}
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
)

add_executable(server server.cpp data_service.pb.cc data_service.grpc.pb.cc)
target_link_libraries(server gRPC::grpc++ protobuf::libprotobuf)
EOF

    cat << 'EOF' > /home/user/client/client_v2.py
# Legacy python 2 client
print "Running python 2 client..."
EOF

    chmod -R 777 /home/user
