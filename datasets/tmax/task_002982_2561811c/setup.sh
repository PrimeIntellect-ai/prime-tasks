#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip \
        protobuf-compiler-grpc libgrpc++-dev libprotobuf-dev \
        protobuf-compiler \
        wget curl build-essential git

    pip3 install pytest

    # Install newer Go to avoid build errors with modern gRPC
    wget https://go.dev/dl/go1.21.8.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.8.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin

    # Install Go protoc plugins
    go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.31.0
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.3.0
    export PATH=$PATH:$(go env GOPATH)/bin

    # Create encoder_service files
    mkdir -p /home/user/encoder_service

    cat << 'EOF' > /home/user/encoder_service/encoder.proto
syntax = "proto3";
package encoder;
option go_package = "benchmark/encoder";
service EncoderService {
  rpc Encode (EncodeRequest) returns (EncodeResponse) {}
}
message EncodeRequest {
  string text = 1;
}
message EncodeResponse {
  string encoded_text = 1;
}
EOF

    cat << 'EOF' > /home/user/encoder_service/server.cpp
#include <iostream>
#include <memory>
#include <string>
#include <mutex>
#include <grpcpp/grpcpp.h>
#include "encoder.grpc.pb.h"

using grpc::Server;
using grpc::ServerBuilder;
using grpc::ServerContext;
using grpc::Status;
using encoder::EncoderService;
using encoder::EncodeRequest;
using encoder::EncodeResponse;

std::mutex global_mutex;

class EncoderServiceImpl final : public EncoderService::Service {
  Status Encode(ServerContext* context, const EncodeRequest* request,
                EncodeResponse* reply) override {
    // BUG: Global lock destroys concurrency
    std::lock_guard<std::mutex> lock(global_mutex);

    std::string input = request->text();
    std::string rle_output = "";

    // TODO: Implement RLE logic. Currently just copies input.
    rle_output = input; 

    // TODO: Implement Base64 encoding of rle_output. Currently just copies.
    std::string b64_output = rle_output; 

    reply->set_encoded_text(b64_output);
    return Status::OK;
  }
};

void RunServer() {
  std::string server_address("0.0.0.0:50051");
  EncoderServiceImpl service;
  ServerBuilder builder;
  builder.AddListeningPort(server_address, grpc::InsecureServerCredentials());
  builder.RegisterService(&service);
  std::unique_ptr<Server> server(builder.BuildAndStart());
  server->Wait();
}

int main(int argc, char** argv) {
  RunServer();
  return 0;
}
EOF

    cat << 'EOF' > /home/user/encoder_service/Makefile
all: encoder_server

encoder.pb.cc encoder.grpc.pb.cc: encoder.proto
	protoc -I . --cpp_out=. encoder.proto
	protoc -I . --grpc_out=. --plugin=protoc-gen-grpc=`which grpc_cpp_plugin` encoder.proto

encoder_server: encoder.pb.cc encoder.grpc.pb.cc server.cpp
	g++ -std=c++17 server.cpp encoder.pb.cc encoder.grpc.pb.cc -o encoder_server
	# BUG: Missing -lgrpc++ -lprotobuf -lpthread
EOF

    # Setup benchmark client
    mkdir -p /app/benchmark/encoder
    cp /home/user/encoder_service/encoder.proto /app/benchmark/encoder/

    cd /app/benchmark
    go mod init benchmark
    go get google.golang.org/grpc@v1.59.0
    go get google.golang.org/protobuf@v1.31.0

    protoc --go_out=. --go_opt=paths=source_relative \
        --go-grpc_out=. --go-grpc_opt=paths=source_relative \
        encoder/encoder.proto

    cat << 'EOF' > main.go
package main

import (
	"context"
	"encoding/base64"
	"fmt"
	"log"
	"sync"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	pb "benchmark/encoder"
)

func main() {
	conn, err := grpc.Dial("localhost:50051", grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatalf("did not connect: %v", err)
	}
	defer conn.Close()
	c := pb.NewEncoderServiceClient(conn)

	// Correctness check
	req := &pb.EncodeRequest{Text: "AAAABBBCCDAA"}
	res, err := c.Encode(context.Background(), req)
	if err != nil {
		log.Fatalf("could not encode: %v", err)
	}
	expectedRLE := "A4B3C2D1A2"
	expectedB64 := base64.StdEncoding.EncodeToString([]byte(expectedRLE))
	if res.EncodedText != expectedB64 {
		log.Fatalf("Correctness check failed. Expected %s, got %s", expectedB64, res.EncodedText)
	}

	// Benchmark
	numWorkers := 100
	reqsPerWorker := 500
	var wg sync.WaitGroup
	wg.Add(numWorkers)

	start := time.Now()
	for i := 0; i < numWorkers; i++ {
		go func() {
			defer wg.Done()
			for j := 0; j < reqsPerWorker; j++ {
				_, _ = c.Encode(context.Background(), req)
			}
		}()
	}
	wg.Wait()
	elapsed := time.Since(start).Seconds()
	totalReqs := numWorkers * reqsPerWorker
	rps := float64(totalReqs) / elapsed

	fmt.Printf("Result: %d RPS\n", int(rps))
}
EOF

    go build -ldflags="-s -w" -o /app/benchmark_client main.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
