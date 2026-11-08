#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/ci_project

    cat << 'EOF' > /home/user/ci_project/Makefile
CXX = g++
CXXFLAGS = -O2

all: app

app: main.o parser.o
	$(CXX) $(CXXFLAGS) -o app main.o parser.o

main.o: main.cpp parser.h
	$(CXX) $(CXXFLAGS) -c main.cpp

parser.o: parser.cpp parser.h
	$(CXX) $(CXXFLAGS) -c parser.cpp

clean:
	rm -f *.o app
EOF

    cat << 'EOF' > /home/user/ci_project/parser.h
#pragma once
#include <string_view>
#include <map>
#include <string>

std::map<std::string_view, std::string_view> parse_payload(std::string_view payload);
EOF

    cat << 'EOF' > /home/user/ci_project/parser.cpp
#include "parser.h"

std::map<std::string_view, std::string_view> parse_payload(std::string_view payload) {
    std::map<std::string_view, std::string_view> res;
    size_t pos = 0;
    while (pos < payload.size()) {
        size_t colon = payload.find(':', pos);
        if (colon == std::string_view::npos) break;
        size_t pipe = payload.find('|', colon);
        if (pipe == std::string_view::npos) break;

        std::string_view key = payload.substr(pos, colon - pos);
        std::string_view val = payload.substr(colon + 1, pipe - colon - 1);
        res[key] = val;

        pos = pipe + 1;
    }
    return res;
}
EOF

    cat << 'EOF' > /home/user/ci_project/main.cpp
#include <iostream>
#include <fstream>
#include <string>
#include "parser.h"

std::string generate_payload() {
    return "CMD:INIT|TARGET:PROD|USER:ADMIN|";
}

int main() {
    // BUG: generate_payload() returns a temporary std::string.
    // parse_payload accepts a string_view to this temporary and returns a map of string_views.
    // The temporary is destroyed at the end of this statement.
    auto parsed = parse_payload(generate_payload());

    std::ofstream out("/home/user/ci_project/output.log");
    out << "TARGET=" << parsed["TARGET"] << "\n";
    out << "USER=" << parsed["USER"] << "\n";
    out.close();
    return 0;
}
EOF

    chmod -R 777 /home/user
