#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang protobuf-compiler
    pip3 install pytest grpcio grpcio-tools hypothesis

    mkdir -p /app/vendored/service-mesh/server/config
    mkdir -p /app/vendored/service-mesh/server/models
    mkdir -p /app/vendored/service-mesh/server/proto
    mkdir -p /app/vendored/service-mesh/proto
    mkdir -p /app/vendored/service-mesh/client

    cat << 'EOF' > /app/vendored/service-mesh/proto/service.proto
syntax = "proto3";
package service;
option go_package = "server/proto";

service EchoService {
  rpc Echo (EchoRequest) returns (EchoResponse);
}

message EchoRequest {
  string payload = 1;
}

message EchoResponse {
  string payload = 1;
}
EOF

    cat << 'EOF' > /app/vendored/service-mesh/server/go.mod
module server

go 1.18

require (
	google.golang.org/grpc v1.50.1
	google.golang.org/protobuf v1.28.1
)
EOF

    cat << 'EOF' > /app/vendored/service-mesh/server/config/config.go
package config

import "server/models"

type Config struct {
    Model *models.Model
}
EOF

    cat << 'EOF' > /app/vendored/service-mesh/server/models/models.go
package models

import "server/config"

type Model struct {
    Config *config.Config
}
EOF

    cat << 'EOF' > /app/vendored/service-mesh/server/main.go
package main

import (
	"context"
	"log"
	"net"
	"server/config"
	"server/models"
	pb "server/proto"
	"google.golang.org/grpc"
)

type server struct {
	pb.UnimplementedEchoServiceServer
}

func (s *server) Echo(ctx context.Context, in *pb.EchoRequest) (*pb.EchoResponse, error) {
	return &pb.EchoResponse{Payload: in.GetPayload()}, nil
}

func main() {
	_ = config.Config{}
	_ = models.Model{}
	lis, err := net.Listen("tcp", ":50051")
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}
	s := grpc.NewServer()
	pb.RegisterEchoServiceServer(s, &server{})
	if err := s.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}
EOF

    cat << 'EOF' > /app/vendored/service-mesh/client/benchmark.py
import grpc
import time
import service_pb2
import service_pb2_grpc

def run():
    channel = grpc.insecure_channel('localhost:50051')
    stub = service_pb2_grpc.EchoServiceStub(channel)
    start = time.time()
    for _ in range(10000):
        stub.Echo(service_pb2.EchoRequest(payload="test"))
    end = time.time()
    rps = 10000 / (end - start)
    with open("/app/throughput.txt", "w") as f:
        f.write(str(rps))

if __name__ == '__main__':
    run()
EOF

    cd /app/vendored/service-mesh/server
    go mod tidy
    go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.28
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.2
    export PATH=$PATH:$(go env GOPATH)/bin
    protoc -I../proto --go_out=. --go-grpc_out=. ../proto/service.proto

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
