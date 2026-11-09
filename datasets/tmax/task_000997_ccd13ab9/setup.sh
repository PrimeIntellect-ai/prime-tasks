#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make socat curl wget
    pip3 install pytest

    mkdir -p /app/vendored/microserver

    # Download actual cpp-httplib header so the server can compile and run
    wget -qO /app/vendored/microserver/httplib.h https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.11.2/httplib.h

    cat << 'EOF' > /app/vendored/microserver/server.cpp
#include "httplib.h"
#include <iostream>

int main(int argc, char** argv) {
    if (argc != 3) {
        std::cerr << "Usage: " << argv[0] << " <port> <base_dir>\n";
        return 1;
    }
    int port = std::stoi(argv[1]);
    std::string base_dir = argv[2];

    httplib::Server svr;
    if (!svr.set_mount_point("/", base_dir)) {
        std::cerr << "Failed to mount base directory\n";
        return 1;
    }
    svr.Get("/health", [](const httplib::Request &, httplib::Response &res) {
        res.set_content("OK", "text/plain");
    });

    std::cout << "Starting server on port " << port << "...\n";
    svr.listen("127.0.0.1", port);
    return 0;
}
EOF

    cat << 'EOF' > /app/vendored/microserver/Makefile
CXX = g++
CXXFLAGS = -std=c++11 -O2
LDFLAGS = 

microserver: server.cpp
	$(CXX) $(CXXFLAGS) -o microserver server.cpp $(LDFLAGS)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
