#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip wget gcc make protobuf-compiler
pip3 install pytest

# Install Go 1.20
wget https://go.dev/dl/go1.20.14.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.20.14.linux-amd64.tar.gz
rm go1.20.14.linux-amd64.tar.gz
export PATH=/usr/local/go/bin:$PATH
ln -s /usr/local/go/bin/go /usr/local/bin/go

# Install protoc-gen-go and protoc-gen-go-grpc
export GOPATH=/opt/go
go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.31.0
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.3.0
ln -s /opt/go/bin/protoc-gen-go /usr/local/bin/
ln -s /opt/go/bin/protoc-gen-go-grpc /usr/local/bin/

mkdir -p /home/user/token-env
cd /home/user/token-env

cat << 'EOF' > service.proto
syntax = "proto3";
package auth;
option go_package = "./auth";

service AuthService {
  rpc ValidateToken (TokenRequest) returns (TokenResponse) {}
}

message TokenRequest {
  string token = 1;
}

message TokenResponse {
  string status = 1;
}
EOF

cat << 'EOF' > legacy_crypto.h
#ifndef LEGACY_CRYPTO_H
#define LEGACY_CRYPTO_H

char* validate_token_c(const char* input);

#endif
EOF

cat << 'EOF' > legacy_crypto.c
#include <stdlib.h>
#include <string.h>
#include "legacy_crypto.h"

char* validate_token_c(const char* input) {
    // BUG: Allocating too little memory for the signature response.
    char* result = (char*)malloc(16);
    if (input && strlen(input) >= 32) {
        // Simulating crypto signature generation
        strcpy(result, "VALIDATION_SUCCESS: 8a9d1c7e6b5f4a3d2c1e0f9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c");
    } else {
        strcpy(result, "INVALID");
    }
    return result;
}
EOF

cat << 'EOF' > Makefile
all: liblegacy_crypto.so

liblegacy_crypto.so: legacy_crypto.c
	gcc -o liblegacy_crypto.so legacy_crypto.c

clean:
	rm -f *.so
EOF

cat << 'EOF' > server.go
package main

import (
	"context"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"

	pb "token-env/auth"

	"google.golang.org/grpc"
)

/*
#cgo LDFLAGS: -L. -llegacy_crypto
#include <stdlib.h>
#include "legacy_crypto.h"
*/
import "C"
import "unsafe"

type server struct {
	pb.UnimplementedAuthServiceServer
}

func (s *server) ValidateToken(ctx context.Context, in *pb.TokenRequest) (*pb.TokenResponse, error) {
	cToken := C.CString(in.Token)
	defer C.free(unsafe.Pointer(cToken))

	cResult := C.validate_token_c(cToken)
	defer C.free(unsafe.Pointer(cResult))

	return &pb.TokenResponse{Status: C.GoString(cResult)}, nil
}

func main() {
	lis, err := net.Listen("tcp", ":50051")
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}
	s := grpc.NewServer()
	pb.RegisterAuthServiceServer(s, &server{})

	go func() {
		if err := s.Serve(lis); err != nil {
			log.Fatalf("failed to serve: %v", err)
		}
	}()

	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt, syscall.SIGTERM)
	<-c
}
EOF

cat << 'EOF' > client.go
package main

import (
	"context"
	"fmt"
	"log"
	"time"

	pb "token-env/auth"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func main() {
	conn, err := grpc.Dial("localhost:50051", grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatalf("did not connect: %v", err)
	}
	defer conn.Close()
	c := pb.NewAuthServiceClient(conn)

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	// Sending a 32-byte token to trigger the C code path
	r, err := c.ValidateToken(ctx, &pb.TokenRequest{Token: "12345678901234567890123456789012"})
	if err != nil {
		log.Fatalf("could not validate: %v", err)
	}
	fmt.Printf("%s\n", r.GetStatus())
}
EOF

cat << 'EOF' > go.mod
module token-env

go 1.20

require (
	google.golang.org/grpc v1.59.0
	google.golang.org/protobuf v1.31.0
)
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
