#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake build-essential
    pip3 install pytest

    mkdir -p /home/user/wsee/src
    mkdir -p /home/user/wsee/include

    cat << 'EOF' > /home/user/wsee/include/ast.h
#ifndef AST_H
#define AST_H
#include <string>
bool parse_and_validate_json(const std::string& json_str);
#endif
EOF

    cat << 'EOF' > /home/user/wsee/src/ast.cpp
#include "ast.h"
bool parse_and_validate_json(const std::string& json_str) {
    // Dummy validation that ensures strict mode compilation works
    #ifdef STRICT_SECURITY
    if (json_str.empty()) return false;
    #endif
    return true; // We assume Python sends valid JSON for this task
}
EOF

    cat << 'EOF' > /home/user/wsee/src/wsee.cpp
#include "ast.h"
#include <iostream>
#include <string>

extern "C" {
    struct WebRequest {
        int ip_version;
        int payload_size;
        int contains_sql;
    };

    int evaluate_ast(const char* ast_json, struct WebRequest* req) {
        if (!ast_json || !req) return -1;
        std::string json(ast_json);
        if (!parse_and_validate_json(json)) return -1;

        // A minimal pseudo-evaluator just for verification of the python output
        // The task asks python to build a JSON tree. We'll simply check if the 
        // JSON contains expected substrings to return 1 (True).
        if (json.find("\"req.ip_version\"") != std::string::npos &&
            json.find("\"operator\": \"==\"") != std::string::npos &&
            json.find("\"right\": 4") != std::string::npos &&
            json.find("\"operator\": \"AND\"") != std::string::npos &&
            req->ip_version == 4 && req->payload_size < 1000 && req->contains_sql == 0) {
            return 1;
        }
        return 0;
    }
}
EOF

    cat << 'EOF' > /home/user/wsee/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(WSEE)

set(CMAKE_CXX_STANDARD 14)

# Bug 1: No fPIC for static library that goes into shared library
add_library(ast STATIC src/ast.cpp)

# Bug 2: Missing target_link_libraries for wsee to use ast
add_library(wsee SHARED src/wsee.cpp)
target_include_directories(wsee PRIVATE include)

# Missing conditional flag handling
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
