#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake g++ golang tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /home/user/workspace/cpp /home/user/workspace/go
    mkdir -p /app

    cat << 'EOF' > /home/user/workspace/cpp/processor.h
#pragma once
void process_array(int* arr, int size);
EOF

    cat << 'EOF' > /home/user/workspace/cpp/processor.cpp
#include "processor.h"
void process_array(int* arr, int size) {
    for(int i=0; i<size; ++i) {
        arr[i] *= 2;
    }
}
EOF

    cat << 'EOF' > /home/user/workspace/cpp/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(DataProcessor)
add_library(processor SHARED processor.cpp)
EOF

    cat << 'EOF' > /home/user/workspace/go/server.go
package main

/*
#cgo CFLAGS: -I../cpp
// BUG: Missing LDFLAGS for the library path and name
#include "processor.h"
*/
import "C"
import (
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"strings"
	"os"
)

type Request struct {
	Data []int `json:"data"`
}

type Response struct {
	Result []int `json:"result"`
}

func main() {
    // Agent must implement auth, port from OCR, and concurrency here
}
EOF

    # Generate the spec image
    convert -background white -fill black -font DejaVu-Sans -pointsize 24 label:"SYSTEM SPECIFICATION\n--------------------\nPORT: 8080\nAUTH_TOKEN: SecretSysAdminKey123" /app/spec.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
