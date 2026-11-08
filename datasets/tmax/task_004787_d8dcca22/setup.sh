#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget protobuf-compiler espeak
    pip3 install pytest

    # Install Go 1.23
    wget https://go.dev/dl/go1.23.4.linux-amd64.tar.gz
    rm -rf /usr/local/go && tar -C /usr/local -xzf go1.23.4.linux-amd64.tar.gz
    rm go1.23.4.linux-amd64.tar.gz
    export PATH=/usr/local/go/bin:$PATH

    # Install protoc-gen-go globally
    export GOPATH=/usr/local/gopath
    export PATH=$GOPATH/bin:$PATH
    go install google.golang.org/protobuf/cmd/protoc-gen-go@latest

    # Setup /app directory
    mkdir -p /app

    # Create voice memo
    espeak -w /app/voice_memo.wav "To encode the asset metadata, first reverse the input string completely, and then encode the reversed string using standard base64."

    # Build reference oracle
    mkdir -p /app/ref
    cd /app/ref
    cat << 'EOF' > metadata.proto
syntax = "proto3";
option go_package = "./pb";
message AssetInfo {
    string data = 1;
    int32 original_length = 2;
}
EOF

    cat << 'EOF' > main.go
package main

import (
	"encoding/base64"
	"io"
	"os"
	"strings"

	"google.golang.org/protobuf/proto"
	"encoder/pb"
)

func reverse(s string) string {
	runes := []rune(s)
	for i, j := 0, len(runes)-1; i < j; i, j = i+1, j-1 {
		runes[i], runes[j] = runes[j], runes[i]
	}
	return string(runes)
}

func main() {
	inputBytes, _ := io.ReadAll(os.Stdin)
	inputStr := strings.TrimSuffix(string(inputBytes), "\n")
	origLen := len(inputStr)

	reversed := reverse(inputStr)
	encoded := base64.StdEncoding.EncodeToString([]byte(reversed))

	msg := &pb.AssetInfo{
		Data:           encoded,
		OriginalLength: int32(origLen),
	}

	outBytes, _ := proto.Marshal(msg)
	os.Stdout.Write(outBytes)
}
EOF

    go mod init encoder
    go get google.golang.org/protobuf/proto
    protoc --go_out=. metadata.proto
    go build -o /app/ref_encoder main.go

    cd /
    rm -rf /app/ref

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
