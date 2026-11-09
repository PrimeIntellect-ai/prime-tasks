#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git build-essential
    pip3 install pytest

    mkdir -p /app/libsensordata/src
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    cd /app/libsensordata
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    cat << 'EOF' > Makefile
all:
	g++ -o test_bin src/encoder.cpp
check: all
	./test_bin
EOF

    cat << 'EOF' > src/encoder.cpp
#include <iostream>
#include <cstring>
void serialize(double double_val, char* buf) {
    memcpy(buf, &double_val, sizeof(double));
}
int main() { return 0; }
EOF

    git add .
    git commit -m "Initial commit"
    git tag v1.1.0

    for i in $(seq 1 92); do
        echo "// commit $i" >> src/encoder.cpp
        git commit -am "Commit $i"
    done

    cat << 'EOF' > src/encoder.cpp
#include <iostream>
#include <cstring>
void serialize(double double_val, char* buf) {
    float f = static_cast<float>(double_val); memcpy(buf, &f, sizeof(float));
}
int main() { return 0; }
EOF
    git commit -am "Optimize serialization for telemetry payloads"

    for i in $(seq 1 107); do
        echo "// commit after regression $i" >> src/encoder.cpp
        git commit -am "Commit after regression $i"
    done

    for i in $(seq 1 50); do
        echo "clean data $i" > /app/corpora/clean/payload_$i.dat
        echo "evil data $i" > /app/corpora/evil/payload_$i.dat
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
