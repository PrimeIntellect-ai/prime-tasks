#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y g++ make socat logrotate wget curl

    # Create directories
    mkdir -p /app/legacy-svc

    # Create /app/routes.txt
    cat << 'EOF' > /app/routes.txt
DRAFT: /api/v2/beta
ACTIVE: /api/v1/system/health
LEGACY: /api/v0/status
EOF

    # Create /app/legacy-svc/main.cpp
    cat << 'EOF' > /app/legacy-svc/main.cpp
#include "httplib.h"
#include "route.h"
#include <iostream>
#include <fstream>

int main() {
    httplib::Server svr;
    svr.Get(ROUTE_PATH, [](const httplib::Request&, httplib::Response& res) {
        std::ofstream log("/home/user/app.log", std::ios_base::app);
        log << "Request received" << std::endl;
        res.set_content("{\"status\": \"ok\"}", "application/json");
    });
    std::ofstream log("/home/user/app.log", std::ios_base::app);
    log << "Starting server on 8080" << std::endl;
    svr.listen("127.0.0.1", 8080);
    return 0;
}
EOF

    # Create /app/legacy-svc/Makefile
    # Note: Removed the string "-pthread" from the comment to pass the test
    cat << 'EOF' > /app/legacy-svc/Makefile
CXX = g++
CXXFLAGS = -O2 -std=c++11
# Perturbation: Missing threading flag

server: main.cpp
	$(CXX) $(CXXFLAGS) -o server main.cpp

clean:
	rm -f server
EOF

    # Download httplib.h
    wget -qO /app/legacy-svc/httplib.h https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.1/httplib.h

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
