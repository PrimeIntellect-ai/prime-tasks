#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make zlib1g-dev wget gzip
    pip3 install pytest

    mkdir -p /home/user/dataset
    echo "dummy binary data" | gzip > /home/user/dataset/001.wal.gz

    mkdir -p /app/wal-serve-v1.0
    wget -qO /app/wal-serve-v1.0/httplib.h https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.1/httplib.h

    cat << 'EOF' > /app/wal-serve-v1.0/Makefile
CXX = g++
CXXFLAGS = -std=c++11 -Wall -I.
LDFLAGS = -pthread

wal_server: server.o
	$(CXX) -o $@ $^ $(LDFLAGS)

server.o: server.cpp
	$(CXX) $(CXXFLAGS) -c $<
EOF

    cat << 'EOF' > /app/wal-serve-v1.0/server.cpp
#include "httplib.h"
#include <zlib.h>
#include <iostream>
#include <string>

// BUG: Wrong path
#define DATA_DIR "/var/old_data"

int main(int argc, char** argv) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <port>\n";
        return 1;
    }
    int port = std::stoi(argv[1]);
    httplib::Server svr;

    svr.Get("/records", [](const httplib::Request &, httplib::Response &res) {
        gzFile file = gzopen(DATA_DIR "/001.wal.gz", "rb");
        if (!file) {
            res.status = 500;
            res.set_content("{\"error\": \"dataset not found\"}", "application/json");
            return;
        }
        char buffer[128];
        int bytes_read = gzread(file, buffer, sizeof(buffer) - 1);
        gzclose(file);

        if (bytes_read > 0) {
            buffer[bytes_read] = '\0';
            res.set_content("{\"status\": \"success\", \"records\": 1}", "application/json");
        } else {
            res.status = 500;
            res.set_content("{\"error\": \"read failed\"}", "application/json");
        }
    });

    std::cout << "Starting server on port " << port << std::endl;
    svr.listen("127.0.0.1", port);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
