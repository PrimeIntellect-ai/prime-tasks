#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends python3 python3-pip g++ make imagemagick fonts-dejavu-core tesseract-ocr tesseract-ocr-eng
    pip3 install pytest

    mkdir -p /opt/oracle
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <cstdlib>
#include <cstdint>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    uint64_t seed = std::strtoull(argv[1], nullptr, 10);
    uint64_t multiplier = 48271;
    uint64_t modulus = 2147483647;
    uint64_t val = seed;
    for(int i=0; i<1000; i++) {
        val = (val * multiplier) % modulus;
    }
    std::cout << val << "\n";
    return 0;
}
EOF
    g++ -O3 /tmp/oracle.cpp -o /opt/oracle/engine && rm /tmp/oracle.cpp

    mkdir -p /home/user/project
    cat << 'EOF' > /home/user/project/main.cpp
#include <iostream>
#include <cstdlib>
// BUG 1: Missing <cstdint> for uint64_t

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    uint64_t seed = std::strtoull(argv[1], nullptr, 10);

    // BUG 2: Incorrect constants causing statistical anomalies
    uint64_t multiplier = 12345;
    uint64_t modulus = 9999999;

    uint64_t val = seed;
    for(int i=0; i<1000; i++) {
        val = (val * multiplier) % modulus;
    }

    std::cout << val << "\n";
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/Makefile
engine: main.cpp
	g++ -Wall -Werror main.cpp -o engine
EOF

    mkdir -p /app
    convert -size 600x100 xc:white -font DejaVu-Sans -pointsize 18 -fill black -draw "text 10,40 'DEBUG MEMORY DUMP: state_ptr->multiplier=48271, state_ptr->modulus=2147483647'" /app/debug_snapshot.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
