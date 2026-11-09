#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make curl tar gzip
    pip3 install pytest

    mkdir -p /home/user/data /app/docserve-1.0

    cat << 'EOF' > /home/user/data/index.csv
101,intro.md
102,advanced/io.md
EOF

    mkdir -p /tmp/raw_docs/advanced
    echo "Introduction to Data Parsing" > /tmp/raw_docs/intro.md
    echo "Advanced C++ File I/O" > /tmp/raw_docs/advanced/io.md
    tar -czf /home/user/data/raw_docs.tar.gz -C /tmp/raw_docs intro.md advanced/io.md

    cat << 'EOF' > /app/docserve-1.0/Makefile
all:
	g++ server.cpp -o server -std=c++11
EOF

    cat << 'EOF' > /app/docserve-1.0/server.cpp
#include "httplib.h"
#include <iostream>
#include <string>
#include <fstream>
#include <unistd.h>

void setup_docs(const std::string& csv_path) {
    // TODO: Implement CSV parsing and symlink creation
}

int main() {
    setup_docs("/home/user/data/index.csv");
    httplib::Server svr;
    auto ret = svr.set_mount_point("/", "/home/user/www");
    if (!ret) {
        std::cerr << "Failed to mount /home/user/www" << std::endl;
        return 1;
    }
    std::cout << "Starting server on port 8080..." << std::endl;
    svr.listen("127.0.0.1", 8080);
    return 0;
}
EOF

    curl -sL -o /app/docserve-1.0/httplib.h https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.1/httplib.h

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
