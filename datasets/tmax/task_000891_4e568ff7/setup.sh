#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential patch binutils
    pip3 install pytest

    mkdir -p /home/user/waf_project
    cd /home/user/waf_project

    cat << 'EOF' > parser.h
#ifndef PARSER_H
#define PARSER_H

#include <string>
#include <vector>

class PayloadParser {
public:
    PayloadParser();
    ~PayloadParser();
    bool analyze(const std::string& payload);
private:
    std::vector<std::string> signatures;
};

#endif
EOF

    cat << 'EOF' > parser.cpp
#include "parser.h"

PayloadParser::PayloadParser() {
    signatures.push_back("DROP TABLE");
}

PayloadParser::~PayloadParser() {}

bool PayloadParser::analyze(const std::string& payload) {
    for (const auto& sig : signatures) {
        if (payload.find(sig) != std::string::npos) {
            return true;
        }
    }
    return false;
}
EOF

    cat << 'EOF' > main.cpp
#include <iostream>
#include <fstream>
#include <string>
#include "parser.h"

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <logfile>\n";
        return 1;
    }

    std::ifstream infile(argv[1]);
    if (!infile.is_open()) {
        std::cerr << "Error opening file\n";
        return 1;
    }

    PayloadParser parser;
    std::string line;
    while (std::getline(infile, line)) {
        if (parser.analyze(line)) {
            std::cout << "BLOCKED: " << line << "\n";
        } else {
            std::cout << "ALLOWED: " << line << "\n";
        }
    }

    return 0;
}
EOF

    cat << 'EOF' > update_signatures.patch
--- parser.cpp	2023-10-24 10:00:00.000000000 +0000
+++ parser_patched.cpp	2023-10-24 10:01:00.000000000 +0000
@@ -2,6 +2,9 @@

 PayloadParser::PayloadParser() {
     signatures.push_back("DROP TABLE");
+    signatures.push_back("<script>");
+    signatures.push_back("UNION SELECT");
+    signatures.push_back("OR 1=1");
 }

 PayloadParser::~PayloadParser() {}
EOF

    cat << 'EOF' > requests.log
GET /index.html HTTP/1.1
POST /login HTTP/1.1 payload="admin' OR 1=1 --"
GET /search?q=<script>alert(1)</script> HTTP/1.1
GET /about HTTP/1.1
POST /api/data HTTP/1.1 payload="DROP TABLE users;"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
