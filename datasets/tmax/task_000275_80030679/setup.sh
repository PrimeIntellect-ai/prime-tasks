#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget protobuf-compiler
    pip3 install pytest

    # Install Go 1.23 to satisfy protobuf requirements
    wget https://go.dev/dl/go1.23.0.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.23.0.linux-amd64.tar.gz
    rm go1.23.0.linux-amd64.tar.gz
    ln -s /usr/local/go/bin/go /usr/local/bin/go
    ln -s /usr/local/go/bin/gofmt /usr/local/bin/gofmt

    export PATH=/usr/local/go/bin:$PATH

    # Install protoc plugins for Go
    go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
    cp ~/go/bin/protoc-gen-go /usr/local/bin/
    cp ~/go/bin/protoc-gen-go-grpc /usr/local/bin/

    # Setup workspace
    mkdir -p /home/user/workspace/migration
    cd /home/user/workspace
    go mod init workspace
    go get google.golang.org/grpc
    go get google.golang.org/protobuf

    cat << 'EOF' > /home/user/workspace/client.go
package main

import (
	"context"
	"log"
	"os"
	"time"

	pb "workspace/migration"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func main() {
	conn, err := grpc.Dial("localhost:50051", grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatalf("did not connect: %v", err)
	}
	defer conn.Close()
	c := pb.NewPatcherClient(conn)

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	req := &pb.PatchRequest{
		Changes: []*pb.Change{
			{Op: pb.Op_KEEP, Line: "from setuptools import setup"},
			{Op: pb.Op_DELETE, Line: "print 'Installing package...'"},
			{Op: pb.Op_ADD, Line: "print('Installing package...')"},
			{Op: pb.Op_KEEP, Line: "setup("},
			{Op: pb.Op_KEEP, Line: "    name='mypkg',"},
			{Op: pb.Op_KEEP, Line: "    version='1.0',"},
			{Op: pb.Op_KEEP, Line: ")"},
		},
	}

	r, err := c.Apply(ctx, req)
	if err != nil {
		log.Fatalf("could not patch: %v", err)
	}

	err = os.WriteFile("/home/user/workspace/patched.py", []byte(r.GetPatchedCode()), 0644)
	if err != nil {
		log.Fatalf("could not write file: %v", err)
	}
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
