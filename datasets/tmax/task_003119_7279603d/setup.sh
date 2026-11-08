#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake make g++ gcc git binutils
    pip3 install pytest

    mkdir -p /app/lib
    mkdir -p /app/fast-log-grep/src
    mkdir -p /app/test_data

    # Create libqueryengine.so
    cat << 'EOF' > /tmp/libqueryengine.cpp
#include <string>
extern "C" {
    bool match_log_fast(const char* line) {
        std::string s(line);
        return s.find("ERROR") != std::string::npos;
    }
    bool match_log_deep(const char* line) {
        std::string s(line);
        return s.find("ERROR") != std::string::npos;
    }
}
EOF
    g++ -shared -fPIC -o /app/lib/libqueryengine.so /tmp/libqueryengine.cpp
    rm /tmp/libqueryengine.cpp

    # Create fast-log-grep repo
    cd /app/fast-log-grep
    cat << 'EOF' > CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(fast-log-grep)
add_executable(fast-log-grep src/parser.cpp)
target_link_directories(fast-log-grep PRIVATE /app/lib)
target_link_libraries(fast-log-grep PRIVATE queryengine)
EOF

    cat << 'EOF' > src/parser.cpp
#include <iostream>
#include <fstream>
#include <string>

extern "C" {
    bool match_log_fast(const char* line);
    bool match_log_deep(const char* line);
}

int main(int argc, char** argv) {
    if (argc < 4) return 1;
    std::ifstream file(argv[3]);
    std::string line;
    while (std::getline(file, line)) {
        if (match_log_fast(line.c_str())) {
            // matched
        }
    }
    return 0;
}
EOF

    git init
    git config user.email "ci@example.com"
    git config user.name "CI"
    git add .
    git commit -m "Initial fast version"

    cat << 'EOF' > src/parser.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <regex>

extern "C" {
    bool match_log_fast(const char* line);
    bool match_log_deep(const char* line);
}

int main(int argc, char** argv) {
    if (argc < 4) return 1;
    std::ifstream file(argv[3]);
    std::string line;
    std::regex r(".*(\\[.*?\\]).*ERROR.*");
    while (std::getline(file, line)) {
        if (std::regex_match(line, r)) {
            if (match_log_deep(line.c_str())) {
                // matched
            }
        }
    }
    return 0;
}
EOF

    git add src/parser.cpp
    git commit -m "Update parsing logic to handle edge cases"

    # Generate massive log
    python3 -c "
with open('/app/test_data/massive_log.txt', 'w') as f:
    for i in range(100000):
        f.write(f'[INFO] Line {i} normal log entry\n')
        if i % 100 == 0:
            f.write(f'[ERROR] Line {i} error log entry\n')
        if i % 500 == 0:
            f.write(f'[[[[[[[malformed error log entry ERROR\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
