#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make valgrind
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/pr_review

    cat << 'EOF' > /home/user/pr_review/parse_logs.py
import sys

def is_valid_error_code(code):
    return len(code) == 5 and code.startswith("ERR") and code[3:].isdigit()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    counts = {}
    with open(sys.argv[1], 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 2:
                code = parts[1]
                if is_valid_error_code(code):
                    counts[code] = counts.get(code, 0) + 1
    for k in sorted(counts.keys()):
        print(f"{k}: {counts[k]}")
EOF

    cat << 'EOF' > /home/user/pr_review/utils.h
#ifndef UTILS_H
#define UTILS_H

#include <string>

bool is_valid_error_code(const std::string& code);

#endif
EOF

    cat << 'EOF' > /home/user/pr_review/utils.cpp
#include "utils.h"
#include <cctype>

bool is_valid_error_code(const std::string& code) {
    // TODO: Translate the logic from parse_logs.py to validate the error code
    return false;
}
EOF

    cat << 'EOF' > /home/user/pr_review/log_parser.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <map>
#include "utils.h"

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    std::ifstream file(argv[1]);
    std::string line;
    std::map<std::string, int> counts;

    while (std::getline(file, line)) {
        // Defect: Memory leak
        char* buffer = new char[256];

        size_t space1 = line.find(' ');
        if (space1 != std::string::npos) {
            size_t space2 = line.find(' ', space1 + 1);
            std::string code = line.substr(space1 + 1, (space2 == std::string::npos ? line.length() : space2) - space1 - 1);
            if (is_valid_error_code(code)) {
                counts[code]++;
            }
        }
    }

    for (auto const& pair : counts) {
        std::cout << pair.first << ": " << pair.second << std::endl;
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/pr_review/Makefile
CXX = g++
CXXFLAGS = -std=c++17 -Wall

all: log_parser

# Defect: Missing utils.o dependency and linkage
log_parser: log_parser.o
	$(CXX) $(CXXFLAGS) -o log_parser log_parser.o

log_parser.o: log_parser.cpp utils.h
	$(CXX) $(CXXFLAGS) -c log_parser.cpp

utils.o: utils.cpp utils.h
	$(CXX) $(CXXFLAGS) -c utils.cpp

clean:
	rm -f *.o log_parser
EOF

    cat << 'EOF' > /home/user/pr_review/dummy_logs.txt
2023-10-01 ERR12 User login failed
2023-10-01 ERR99 Database timeout
2023-10-01 INFO01 Service started
2023-10-01 ERR12 Invalid credentials
2023-10-01 ERR05 Connection lost
2023-10-01 ERRXX Unknown error format
EOF

    chmod -R 777 /home/user
