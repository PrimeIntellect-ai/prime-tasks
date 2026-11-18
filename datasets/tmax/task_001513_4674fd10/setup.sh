#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make sqlite3 libsqlite3-dev curl wget
    pip3 install pytest

    mkdir -p /app/vendored/libjsonparse-1.2/src
    mkdir -p /app/vendored/libjsonparse-1.2/include

    cat << 'EOF' > /app/vendored/libjsonparse-1.2/Makefile
CXX = g++
CXXFLAGS = -std=c++17 -Wall -Wextra -I./include

all: libjsonparse.a

libjsonparse.a: src/decoder.o
	ar rcs libjsonparse.a src/decoder.o

src/decoder.o: src/decoder.cpp include/jsonparse.h
    $(CXX) $(CXXFLAGS) -c src/decoder.cpp -o src/decoder.o

clean:
	rm -f src/*.o libjsonparse.a
EOF

    cat << 'EOF' > /app/vendored/libjsonparse-1.2/include/jsonparse.h
#pragma once
#include <string>

namespace jsonparse {
    void parse(const std::string& input);
}
EOF

    cat << 'EOF' > /app/vendored/libjsonparse-1.2/src/decoder.cpp
#include "jsonparse.h"
#include <stdexcept>
#include <string>

namespace jsonparse {
    void parse(const std::string& input) {
        for (size_t i = 0; i < input.length(); ++i) {
            char current_char = input[i];
            char next_char = (i + 1 < input.length()) ? input[i+1] : '\0';
            if (current_char == '\\' && next_char == 'u') {
                throw std::runtime_error("Unicode escapes not supported yet");
            }
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
