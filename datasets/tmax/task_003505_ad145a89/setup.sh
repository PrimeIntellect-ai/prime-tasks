#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip \
        wget \
        imagemagick \
        tesseract-ocr \
        protobuf-compiler \
        fonts-liberation

    pip3 install pytest Levenshtein

    # Install Go 1.23
    wget https://go.dev/dl/go1.23.0.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.23.0.linux-amd64.tar.gz
    rm go1.23.0.linux-amd64.tar.gz
    export PATH=/usr/local/go/bin:/home/user/go/bin:$PATH
    export GOPATH=/home/user/go

    # Install protoc Go plugins
    go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

    # Create the image fixture
    mkdir -p /app
    convert -background white -fill black -font Liberation-Mono -pointsize 24 label:"INVOICE #9981\nDate: 2023-10-01\nTotal: \$1,234.56\nThank you for your business!" /app/invoice.png

    # Setup user and workspace
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/workspace/proto
    mkdir -p /home/user/workspace/server
    mkdir -p /home/user/workspace/client

    chmod -R 777 /home/user
    chmod -R 777 /app
