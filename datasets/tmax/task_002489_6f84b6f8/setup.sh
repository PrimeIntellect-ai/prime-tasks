#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc make curl
    pip3 install pytest

    mkdir -p /app/libmobilemanifest
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create libmobilemanifest Go module
    cd /app/libmobilemanifest
    go mod init libmobilemanifest

    cat << 'EOF' > parser.h
#ifndef PARSER_H
#define PARSER_H

char* parse_mab(const char* input, int length);

#endif
EOF

    cat << 'EOF' > parser.c
#include <string.h>
#include <stdlib.h>
#include "parser.h"

char* parse_mab(const char* input, int length) {
    if (length <= 32) return NULL;
    char buffer[32];
    strncpy(buffer, input, 32);
    buffer[32] = '\0'; // BUG: off by one

    int json_len = length - 32;
    char* json = malloc(json_len + 1);
    memcpy(json, input + 32, json_len);
    json[json_len] = '\0';
    return json;
}
EOF

    cat << 'EOF' > manifest.go
package libmobilemanifest

/*
#cgo CFLAGS: -I.
#include "parser.h"
#include <stdlib.h>
*/
import "C"
import "unsafe"
import "errors"

func ExtractManifest(data []byte) (string, error) {
    if len(data) <= 32 {
        return "", errors.New("data too short")
    }
    cdata := C.CBytes(data)
    defer C.free(cdata)

    cStr := C.parse_mab((*C.char)(cdata), C.int(len(data)))
    if cStr == nil {
        return "", errors.New("failed to parse")
    }
    defer C.free(unsafe.Pointer(cStr))

    return C.GoString(cStr), nil
}
EOF

    cat << 'EOF' > Makefile
build:
	CGO_ENABLED=0 go build ./...
test:
	go test ./...
EOF

    # Create corpora
    # Clean file
    printf "%32s" "HEADER_DATA_12345678901234567890" > /app/corpora/clean/good.mab
    echo '{"version":"v1.0.0","provides":["featureA"],"requires":["featureA"]}' >> /app/corpora/clean/good.mab

    # Evil files
    # Invalid JSON
    printf "%32s" "HEADER_DATA_12345678901234567890" > /app/corpora/evil/bad_json.mab
    echo '{"version":"v1.0.0","provides":[' >> /app/corpora/evil/bad_json.mab

    # Missing requirement
    printf "%32s" "HEADER_DATA_12345678901234567890" > /app/corpora/evil/missing_req.mab
    echo '{"version":"v1.0.0","provides":["featureA"],"requires":["featureB"]}' >> /app/corpora/evil/missing_req.mab

    # Bad version
    printf "%32s" "HEADER_DATA_12345678901234567890" > /app/corpora/evil/bad_version.mab
    echo '{"version":"1.0.0","provides":["featureA"],"requires":["featureA"]}' >> /app/corpora/evil/bad_version.mab

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
