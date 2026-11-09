#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/project/lib-1.5.2 /home/user/project/lib-1.11.0 /home/user/project/lib-2.0.5

    cat << 'EOF' > /home/user/project/lib-1.5.2/mathalg.cpp
extern "C" const char* get_version() { return "1.5.2"; }
extern "C" int compute(int a, int b) { return a + b; }
EOF

    cat << 'EOF' > /home/user/project/lib-1.11.0/mathalg.cpp
extern "C" const char* get_version() { return "1.11.0"; }
extern "C" int compute(int a, int b) { return a + b; }
EOF

    cat << 'EOF' > /home/user/project/lib-2.0.5/mathalg.cpp
extern "C" const char* get_version() { return "2.0.5"; }
extern "C" int compute(int a, int b) { return a + b; }
EOF

    cat << 'EOF' > /home/user/project/test_suite.cpp
#include <iostream>
#include <string>

extern "C" const char* get_version();
extern "C" int compute(int a, int b);

int main() {
    std::string ver = get_version();
    int major = ver[0] - '0';
    if (major < 2) {
        std::cerr << "Test failed: library version " << ver << " is less than 2.0.0" << std::endl;
        return 1;
    }
    if (compute(3, 4) != 7) {
        std::cerr << "Test failed: compute error" << std::endl;
        return 1;
    }
    std::cout << "SUCCESS: Linked version " << ver << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/Makefile
# Finds the library version to build
LATEST_LIB_DIR := $(shell ls -d lib-* | sort | head -n 1)

all: test_suite

libmathalg.so: $(LATEST_LIB_DIR)/mathalg.cpp
	g++ -o libmathalg.so $(LATEST_LIB_DIR)/mathalg.cpp

test_suite: test_suite.cpp libmathalg.so
	g++ -o test_suite test_suite.cpp
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
