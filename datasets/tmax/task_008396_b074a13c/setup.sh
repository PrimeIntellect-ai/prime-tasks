#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        build-essential \
        libseccomp-dev \
        jq \
        binutils

    pip3 install pytest

    mkdir -p /home/user/incident

    cat << 'EOF' > /home/user/incident/auth_server.cpp
#include <iostream>
#include <cstring>
#include <cstdlib>
#include <ctime>
#include <unistd.h>

void generate_token() {
    srand(time(NULL)); // CWE-338: Use of Cryptographically Weak Pseudo-Random Number Generator (PRNG)
    int token = rand();
    std::cout << "Generated Token: " << token << std::endl;
}

void validate_token(const char* input) {
    char buffer[16];
    // CWE-120: Buffer Copy without Checking Size of Input ('Classic Buffer Overflow')
    strcpy(buffer, input); 

    std::cout << "Validating token: " << buffer << std::endl;
    // Dummy validation
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <generate|validate> [token]" << std::endl;
        return 1;
    }

    if (strcmp(argv[1], "generate") == 0) {
        generate_token();
    } else if (strcmp(argv[1], "validate") == 0 && argc == 3) {
        validate_token(argv[2]);
    } else {
        std::cerr << "Invalid arguments." << std::endl;
        return 1;
    }

    return 0;
}
EOF

    cat << 'EOF' > /home/user/incident/Makefile
all: authd

authd: auth_server.cpp
	g++ -O2 -Wall auth_server.cpp -o authd

clean:
	rm -f authd
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/incident
    chmod -R 777 /home/user
