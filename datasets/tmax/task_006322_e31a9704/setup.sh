#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cmake make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/deps/lib
    mkdir -p /home/user/deps/include
    mkdir -p /home/user/project/build

    cat << 'EOF' > /home/user/deps/include/syslogger.h
#ifndef SYSLOGGER_H
#define SYSLOGGER_H
void init_logger();
#endif
EOF

    cat << 'EOF' > /tmp/syslogger.cpp
#include "syslogger.h"
#include <iostream>
void init_logger() {
    // Dummy init
}
EOF

    g++ -fPIC -shared -I/home/user/deps/include -o /home/user/deps/lib/libsyslogger.so /tmp/syslogger.cpp

    cat << 'EOF' > /home/user/project/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(LogParser)

set(CMAKE_CXX_STANDARD 14)

include_directories(/home/user/deps/include)

add_executable(parser main.cpp)

# BUG: Missing link directories or library path config
target_link_libraries(parser syslogger)
EOF

    cat << 'EOF' > /home/user/project/main.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <memory>
#include <algorithm>
#include "syslogger.h"

struct LogEntry {
    std::string data;
};

int main() {
    init_logger();
    std::ifstream in("/home/user/project/input.log");
    std::string line;
    std::vector<std::unique_ptr<LogEntry>> entries;

    while (std::getline(in, line)) {
        if (line.rfind("[OK]", 0) == 0) {
            auto entry = std::make_unique<LogEntry>();
            entry->data = line.substr(5);

            entries.push_back(std::move(entry));

            // BUG: Use after move, will cause segfault
            if (entry->data.empty()) {
                std::cerr << "Empty data" << std::endl;
            }
        }
    }

    std::vector<std::string> results;
    for (auto& e : entries) {
        if (e) {
            results.push_back(e->data);
        }
    }

    std::sort(results.begin(), results.end());

    for (const auto& r : results) {
        std::cout << r << "\n";
    }

    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/input.log
[OK] System booted
[ERR] Disk full
[OK] Network connected
[WARN] High memory
[OK] All services running
[OK] Database initialized
EOF

    chown -R user:user /home/user/deps
    chown -R user:user /home/user/project
    chmod -R 777 /home/user
