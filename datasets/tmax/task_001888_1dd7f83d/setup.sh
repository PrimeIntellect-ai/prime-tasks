#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-pil \
        tesseract-ocr \
        build-essential \
        pkg-config \
        protobuf-compiler-grpc \
        libgrpc++-dev \
        protobuf-compiler \
        libprotobuf-dev

    pip3 install pytest

    mkdir -p /app/workspace

    cat << 'EOF' > /app/workspace/matrix.proto
syntax = "proto3";

package matrix;

service MatrixService {
  rpc CalculateDeterminant (MatrixRequest) returns (MatrixResponse) {}
}

message MatrixRequest {
  repeated float data = 1;
  int32 size = 2;
}

message MatrixResponse {
  float determinant = 1;
}
EOF

    cat << 'EOF' > /app/workspace/numalgo.h
#ifndef NUMALGO_H
#define NUMALGO_H

float calculate_determinant(const float* matrix, int size);

#endif
EOF

    cat << 'EOF' > /app/workspace/numalgo.c
#include "numalgo.h"

float calculate_determinant(const float* matrix, int size) {
    if (size == 1) return matrix[0];
    if (size == 2) return matrix[0] * matrix[3] - matrix[1] * matrix[2];
    if (size == 3) {
        return matrix[0] * (matrix[4] * matrix[8] - matrix[5] * matrix[7])
             - matrix[1] * (matrix[3] * matrix[8] - matrix[5] * matrix[6])
             + matrix[2] * (matrix[3] * matrix[7] - matrix[4] * matrix[6]);
    }
    return 0.0f;
}
EOF

    cat << 'EOF' > /app/workspace/server.cc
#include <iostream>
#include <memory>
#include <string>
#include <fstream>

#include <grpcpp/grpcpp.h>
#include "matrix.grpc.pb.h"
#include "numalgo.h"

using grpc::Server;
using grpc::ServerBuilder;
using grpc::ServerContext;
using grpc::Status;
using grpc::StatusCode;
using matrix::MatrixRequest;
using matrix::MatrixResponse;
using matrix::MatrixService;

class MatrixServiceImpl final : public MatrixService::Service {
    int request_count = 0;
    int rate_limit = 0;

public:
    MatrixServiceImpl() {
        std::ifstream infile("/app/rate_limit.txt");
        if (infile.good()) {
            infile >> rate_limit;
        } else {
            rate_limit = 0;
        }
    }

    Status CalculateDeterminant(ServerContext* context, const MatrixRequest* request, MatrixResponse* reply) override {
        if (rate_limit > 0 && request_count >= rate_limit) {
            return Status(StatusCode::RESOURCE_EXHAUSTED, "Rate limit exceeded");
        }
        request_count++;

        float det = calculate_determinant(request->data().data(), request->size());
        reply->set_determinant(det);
        return Status::OK;
    }
};

void RunServer() {
    std::string server_address("0.0.0.0:50051");
    MatrixServiceImpl service;

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

    cat << 'EOF' > /app/workspace/Makefile
CXX = g++
CPPFLAGS += `pkg-config --cflags protobuf grpc`
CXXFLAGS += -std=c++14
LDFLAGS += -L/usr/local/lib `pkg-config --libs protobuf grpc++` -Wl,--no-as-needed -lgrpc++_reflection -Wl,--as-needed -ldl

PROTOC = protoc
GRPC_CPP_PLUGIN = grpc_cpp_plugin
GRPC_CPP_PLUGIN_PATH ?= `which $(GRPC_CPP_PLUGIN)`

all: server

matrix.pb.cc matrix.pb.h: matrix.proto
	$(PROTOC) -I . --cpp_out=. $<

matrix.grpc.pb.cc matrix.grpc.pb.h: matrix.proto
	$(PROTOC) -I . --grpc_out=. --plugin=protoc-gen-grpc=$(GRPC_CPP_PLUGIN_PATH) $<

numalgo.o: numalgo.c numalgo.h
	gcc -c numalgo.c -o numalgo.o

server.o: server.cc matrix.pb.h matrix.grpc.pb.h numalgo.h
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c server.cc -o server.o

matrix.pb.o: matrix.pb.cc
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c matrix.pb.cc -o matrix.pb.o

matrix.grpc.pb.o: matrix.grpc.pb.cc
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c matrix.grpc.pb.cc -o matrix.grpc.pb.o

server: matrix.pb.o matrix.grpc.pb.o numalgo.o server.o
	$(CXX) $^ $(LDFLAGS) -o $@

clean:
	rm -f *.o *.pb.cc *.pb.h server
EOF

    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (150, 50), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), 'Limit: 5', fill=(0,0,0))
img.save('/app/rate_limit.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
