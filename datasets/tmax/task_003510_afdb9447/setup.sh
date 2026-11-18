#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make wget curl
    pip3 install pytest

    mkdir -p /app/tinyml
    mkdir -p /app/httplib
    mkdir -p /app/json

    cat << 'EOF' > /app/tinyml/tinyml.h
#pragma once
#include <vector>
namespace tinyml {
    double dot_product(const std::vector<double>& a, const std::vector<double>& b);
}
EOF

    cat << 'EOF' > /app/tinyml/tinyml.cpp
#include "tinyml.h"
#include <numeric>
#include <stdexcept>
#include <optional> // Force C++17

namespace tinyml {
    double dot_product(const std::vector<double>& a, const std::vector<double>& b) {
        std::optional<size_t> size_a = a.size();
        if (size_a.value() != b.size()) throw std::invalid_argument("Size mismatch");
        return std::inner_product(a.begin(), a.end(), b.begin(), 0.0);
    }
}
EOF

    cat << 'EOF' > /app/tinyml/Makefile
CXX = g++
CXXFLAGS = -std=c++11 -Wall -O3

all: libtinyml.a

libtinyml.a: tinyml.o
	ar rcs libtinyml.a tinyml.o

tinyml.o: tinyml.cpp tinyml.h
	$(CXX) $(CXXFLAGS) -c tinyml.cpp

clean:
	rm -f *.o *.a
EOF

    wget -q https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.1/httplib.h -O /app/httplib/httplib.h
    wget -q https://raw.githubusercontent.com/nlohmann/json/v3.11.2/single_include/nlohmann/json.hpp -O /app/json/json.hpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
