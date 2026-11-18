#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc golang-go
    pip3 install pytest

    mkdir -p /home/user/waf/db
    mkdir -p /home/user/waf/c_src
    mkdir -p /home/user/waf/go_src/engine
    mkdir -p /home/user/waf/go_src/config

    cat << 'EOF' > /home/user/waf/db/v1_init.sql
CREATE TABLE rules (id INTEGER PRIMARY KEY, pattern TEXT);
INSERT INTO rules (pattern) VALUES ('DROP TABLE');
EOF

    cat << 'EOF' > /home/user/waf/db/v2_update.sql
ALTER TABLE rules ADD COLUMN action TEXT DEFAULT 'BLOCK';
EOF

    cat << 'EOF' > /home/user/waf/c_src/parser.h
#ifndef PARSER_H
#define PARSER_H
char* extract_payload(const char* input);
#endif
EOF

    cat << 'EOF' > /home/user/waf/c_src/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "parser.h"

char* extract_payload(const char* input) {
    char* buffer = (char*)malloc(16);
    // VULNERABILITY: strcpy without bounds checking
    strcpy(buffer, input);
    return buffer;
}
EOF

    cat << 'EOF' > /home/user/waf/go_src/go.mod
module waf

go 1.20
EOF

    cat << 'EOF' > /home/user/waf/go_src/main.go
package main

/*
#cgo CFLAGS: -I../c_src
#cgo LDFLAGS: -L.. -lparser
#include "parser.h"
#include <stdlib.h>
*/
import "C"

import (
    "fmt"
    "os"
    "unsafe"
    "waf/engine"
)

func main() {
    if len(os.Args) < 2 {
        return
    }
    input := os.Args[1]
    cInput := C.CString(input)
    defer C.free(unsafe.Pointer(cInput))

    // Call C function
    cPayload := C.extract_payload(cInput)
    payload := C.GoString(cPayload)
    C.free(unsafe.Pointer(cPayload))

    result := engine.Evaluate(payload)
    fmt.Printf("Payload: %s, Result: %s\n", payload, result)
}
EOF

    cat << 'EOF' > /home/user/waf/go_src/engine/engine.go
package engine

import (
    "waf/config"
)

func Evaluate(payload string) string {
    rule := config.GetDefaultRule()
    if payload == rule.Pattern {
        return "BLOCKED"
    }
    return "ALLOWED"
}
EOF

    cat << 'EOF' > /home/user/waf/go_src/config/config.go
package config

import "waf/engine" // CIRCULAR IMPORT

type Rule struct {
    Pattern string
}

func GetDefaultRule() Rule {
    // Artificial circular use
    _ = engine.Evaluate
    return Rule{Pattern: "DROP TABLE users;"}
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
