#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ws_filter

    cat << 'EOF' > /home/user/ws_filter/Makefile
CXX = g++
CXXFLAGS = -std=c++17 -Wall

# BUG: Missing semver.o in the linking step
ws_filter: main.o policy.o
	$(CXX) $(CXXFLAGS) -o ws_filter main.o policy.o

main.o: main.cpp
	$(CXX) $(CXXFLAGS) -c main.cpp

policy.o: policy.cpp policy.h
	$(CXX) $(CXXFLAGS) -c policy.cpp

semver.o: semver.cpp semver.h
	$(CXX) $(CXXFLAGS) -c semver.cpp

clean:
	rm -f *.o ws_filter
EOF

    cat << 'EOF' > /home/user/ws_filter/main.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <sstream>
#include "policy.h"

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    std::ifstream infile(argv[1]);
    std::string line;
    while (std::getline(infile, line)) {
        std::stringstream ss(line);
        std::string id, client_v, expr;
        std::getline(ss, id, '|');
        std::getline(ss, client_v, '|');
        std::getline(ss, expr);

        // trim spaces
        id.erase(0, id.find_first_not_of(" \t")); id.erase(id.find_last_not_of(" \t") + 1);
        client_v.erase(0, client_v.find_first_not_of(" \t")); client_v.erase(client_v.find_last_not_of(" \t") + 1);
        expr.erase(0, expr.find_first_not_of(" \t")); expr.erase(expr.find_last_not_of(" \t") + 1);

        if (evaluate_policy(client_v, expr)) {
            std::cout << id << std::endl;
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/ws_filter/semver.h
#ifndef SEMVER_H
#define SEMVER_H
#include <string>
bool compare_semver(const std::string& v1, const std::string& op, const std::string& v2);
#endif
EOF

    cat << 'EOF' > /home/user/ws_filter/semver.cpp
#include "semver.h"
#include <vector>
#include <sstream>

std::vector<int> parse_version(const std::string& v) {
    std::vector<int> parts;
    std::stringstream ss(v);
    std::string part;
    while (std::getline(ss, part, '.')) {
        parts.push_back(std::stoi(part));
    }
    while (parts.size() < 3) parts.push_back(0);
    return parts;
}

int compare_versions_raw(const std::string& v1, const std::string& v2) {
    auto p1 = parse_version(v1);
    auto p2 = parse_version(v2);
    for (size_t i = 0; i < 3; ++i) {
        if (p1[i] > p2[i]) return 1;
        if (p1[i] < p2[i]) return -1;
    }
    return 0;
}

bool compare_semver(const std::string& v1, const std::string& op, const std::string& v2) {
    int cmp = compare_versions_raw(v1, v2);
    if (op == "==") return cmp == 0;
    if (op == ">") return cmp > 0;
    if (op == "<") return cmp < 0;
    if (op == ">=") return cmp >= 0;
    if (op == "<=") return cmp <= 0;
    return false;
}
EOF

    cat << 'EOF' > /home/user/ws_filter/policy.h
#ifndef POLICY_H
#define POLICY_H
#include <string>
bool evaluate_policy(const std::string& client_version, const std::string& expression);
#endif
EOF

    cat << 'EOF' > /home/user/ws_filter/policy.cpp
#include "policy.h"
#include "semver.h"
#include <sstream>

bool evaluate_policy(const std::string& client_version, const std::string& expression) {
    // TODO: Implement parsing of `expression` (format: "V [op] [version]")
    // and use compare_semver(client_version, op, version) to return the result.
    return false;
}
EOF

    cat << 'EOF' > /home/user/ws_filter/ws_requests.txt
101 | 1.0.5 | V >= 1.0.0
102 | 0.9.9 | V >= 1.0.0
103 | 2.1.0 | V < 2.0.0
104 | 2.0.0 | V == 2.0.0
105 | 1.12.0 | V > 1.2.0
106 | 1.2.0 | V <= 1.2.0
EOF

    chmod -R 777 /home/user
