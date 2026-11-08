#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip wget curl unzip protobuf-compiler rustc
pip3 install pytest

# Install Go 1.23
wget https://go.dev/dl/go1.23.0.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.23.0.linux-amd64.tar.gz
ln -s /usr/local/go/bin/go /usr/local/bin/go
ln -s /usr/local/go/bin/gofmt /usr/local/bin/gofmt

# Install protoc-gen-go and protoc-gen-go-grpc
export GOPATH=/root/go
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
ln -s /root/go/bin/protoc-gen-go /usr/local/bin/protoc-gen-go
ln -s /root/go/bin/protoc-gen-go-grpc /usr/local/bin/protoc-gen-go-grpc

# Create directories
mkdir -p /home/user/legacy /home/user/service /home/user/formatter /home/user/client

# Legacy Python 2 code
cat << 'EOF' > /home/user/legacy/encrypt.py
def process_string(s):
    # Reverse the string
    reversed_s = s[::-1]
    # Shift ascii values by +1
    result = ""
    for char in reversed_s:
        result += chr(ord(char) + 1)
    return result

if __name__ == "__main__":
    print process_string("test")
EOF

# Broken Rust code
cat << 'EOF' > /home/user/formatter/main.rs
use std::io::{self, Read};

fn main() {
    let mut buffer = String::new();
    io::stdin().read_to_string(&mut buffer).unwrap();

    let processed = format!("{} [MIGRATED]", buffer.trim());

    let borrowed = &processed;
    drop(processed); // Error: drop occurs while still borrowed

    println!("{}", borrowed);
}
EOF

# Go client
cat << 'EOF' > /home/user/client/main.go
package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	pb "client/api" // Assuming the agent places proto in GOPATH or modules correctly, but we'll use a local raw approach for verification.
)

func main() {
	conn, err := grpc.Dial("localhost:9090", grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatalf("did not connect: %v", err)
	}
	defer conn.Close()
	c := pb.NewMigrationServiceClient(conn)

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	r, err := c.ProcessString(ctx, &pb.StringRequest{Payload: "legacy_python_code"})
	if err != nil {
		log.Fatalf("could not process: %v", err)
	}
	fmt.Print(r.GetResult())
}
EOF

# Create the user
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
