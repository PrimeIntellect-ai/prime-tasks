#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /home/user/project
    mkdir -p /home/user/rapidcheck/include
    mkdir -p /home/user/rapidcheck/extras

    # Mock RapidCheck
    cat << 'EOF' > /home/user/rapidcheck/include/rapidcheck.h
#pragma once
#include <iostream>
#include <string>
#include <cassert>
#define RC_GTEST_PROP(test_case_name, test_name, ...) void test_name()
namespace rc {
    template<typename T> T pick();
    template<> std::string pick<std::string>() { return "1.2.3"; }
    void check(const std::string& description, void(*prop)()) { prop(); std::cout << "OK, passed." << std::endl; }
}
EOF

    ar rcs /home/user/rapidcheck/librapidcheck.a

    # Python 2 wrapper
    cat << 'EOF' > /home/user/project/wrapper.py
import sys
import subprocess
import json

def run_solver(req_file):
    print "Running solver on", req_file
    with open(req_file, 'r') as f:
        data = json.load(f)

    # Python 2 specific iteration
    items = []
    for k, v in data.iteritems():
        items.append(k + ":" + v)

    p = subprocess.Popen(['./solver'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    out, err = p.communicate(input="\n".join(items).encode('utf-8'))

    # Python 2 print
    print "Solver output:"
    print out.decode('utf-8')

if __name__ == '__main__':
    if len(sys.argv) > 1:
        run_solver(sys.argv[1])
EOF

    # Buggy C++ Code
    cat << 'EOF' > /home/user/project/semver.h
#pragma once
#include <string>
int compare_versions(const std::string& a, const std::string& b);
EOF

    cat << 'EOF' > /home/user/project/semver.cpp
#include "semver.h"
int compare_versions(const std::string& a, const std::string& b) {
    if (a == b) return 0;
    return a > b ? 1 : -1;
}
EOF

    cat << 'EOF' > /home/user/project/graph.h
#pragma once
#include <string>
#include <vector>
std::string resolve(const std::vector<std::string>& reqs);
EOF

    cat << 'EOF' > /home/user/project/graph.cpp
#include "graph.h"
#include "semver.h"
#include <algorithm>
#include <sstream>

std::string resolve(const std::vector<std::string>& reqs) {
    // Dummy resolution logic for task validation
    // Returns a JSON-like string of resolved versions
    if (reqs.empty()) return "{}";
    if (compare_versions("1.10.0", "1.2.0") == 1) {
        return "{\n  \"status\": \"resolved_correctly\"\n}\n";
    } else {
        return "{\n  \"status\": \"resolved_incorrectly\"\n}\n";
    }
}
EOF

    cat << 'EOF' > /home/user/project/solver.cpp
#include <iostream>
#include <string>
#include <vector>
#include "graph.h"

int main() {
    std::vector<std::string> reqs;
    std::string line;
    while (std::getline(std::cin, line)) {
        if (!line.empty()) reqs.push_back(line);
    }
    std::cout << resolve(reqs);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/input.json
{
    "packageA": ">=1.0.0",
    "packageB": "<2.0.0"
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
