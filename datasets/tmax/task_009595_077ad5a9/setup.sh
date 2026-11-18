#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/api_gateway

    cat << 'EOF' > /home/user/api_gateway/Makefile
CXX = g++
CXXFLAGS = -Wall -std=c++17

all: gateway_tool

gateway_tool: main.o checksum.o rate_limit.o
	$(CXX) $(CXXFLAGS) main.o checksum.o -o gateway_tool

main.o: main.cpp
	$(CXX) $(CXXFLAGS) -c main.cpp

checksum.o: checksum.cpp checksum.h
	$(CXX) $(CXXFLAGS) -c checksum.cpp

rate_limit.o: rate_limit.cpp rate_limit.h
	$(CXX) $(CXXFLAGS) -c rate_limit.cpp

clean:
	rm -f *.o gateway_tool
EOF

    cat << 'EOF' > /home/user/api_gateway/checksum.h
#ifndef CHECKSUM_H
#define CHECKSUM_H
#include <string>
#include <cstdint>

uint16_t calculate_fletcher16(const std::string& data);

#endif
EOF

    cat << 'EOF' > /home/user/api_gateway/checksum.cpp
#include "checksum.h"

uint16_t calculate_fletcher16(const std::string& data) {
    // TODO: Implement Fletcher-16
    return 0;
}
EOF

    cat << 'EOF' > /home/user/api_gateway/rate_limit.h
#ifndef RATE_LIMIT_H
#define RATE_LIMIT_H
#include <string>
#include <unordered_map>

class RateLimiter {
private:
    int max_requests;
    std::unordered_map<std::string, int> request_counts;
public:
    RateLimiter(int max_requests);
    bool allow_request(const std::string& ip);
};

#endif
EOF

    cat << 'EOF' > /home/user/api_gateway/rate_limit.cpp
#include "rate_limit.h"

RateLimiter::RateLimiter(int max_requests) {
    // TODO: Implement
}

bool RateLimiter::allow_request(const std::string& ip) {
    // TODO: Implement
    return true;
}
EOF

    cat << 'EOF' > /home/user/api_gateway/main.cpp
#include <iostream>
#include <string>
#include <cstdlib>
#include "checksum.h"
#include "rate_limit.h"

// Global rate limiter for the simulation (max 3 requests)
static RateLimiter limiter(3);

int main(int argc, char** argv) {
    if (argc != 4) {
        std::cerr << "Usage: gateway_tool <ip> <data> <checksum>\n";
        return 1;
    }

    std::string ip = argv[1];
    std::string data = argv[2];
    uint16_t provided_checksum = std::stoi(argv[3]);

    if (!limiter.allow_request(ip)) {
        std::cout << "RATE_LIMITED\n";
        return 0;
    }

    uint16_t actual_checksum = calculate_fletcher16(data);
    if (actual_checksum != provided_checksum) {
        std::cout << "CHECKSUM_FAILED\n";
        return 0;
    }

    std::cout << "ALLOWED\n";
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/api_gateway
    chmod -R 777 /home/user
