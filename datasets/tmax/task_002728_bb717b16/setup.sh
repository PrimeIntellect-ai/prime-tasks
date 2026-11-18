#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc g++ make binutils libssl-dev
pip3 install pytest

mkdir -p /app/jwt-service/src /app/jwt-service/tls

cat << 'EOF' > /app/legacy_auth.c
#include <stdio.h>
int main() {
    // Hardcoded secret key
    const char* secret = "X9fR2mP7qL4cT1vN8bH5wK3zJ6yD0sA!";
    printf("Auth system initialized.\n");
    return 0;
}
EOF
gcc -O2 /app/legacy_auth.c -o /app/legacy_auth
strip /app/legacy_auth
rm /app/legacy_auth.c

cat << 'EOF' > /app/jwt-service/Makefile
CXX = g++
CXXFLAGS = -std=c++11 -Wall
# DELIBERATE PERTURBATION: missing crypto libs
LDFLAGS = -lpthread

all: jwt_server

jwt_server: src/main.o src/auth.o
	$(CXX) -o jwt_server src/main.o src/auth.o $(LDFLAGS)

src/main.o: src/main.cpp
	$(CXX) $(CXXFLAGS) -c src/main.cpp -o src/main.o

src/auth.o: src/auth.cpp
	$(CXX) $(CXXFLAGS) -c src/auth.cpp -o src/auth.o

clean:
	rm -f jwt_server src/*.o
EOF

cat << 'EOF' > /app/jwt-service/src/auth.h
#ifndef AUTH_H
#define AUTH_H
#include <string>
bool verify_jwt(const std::string& token, const std::string& secret);
#endif
EOF

cat << 'EOF' > /app/jwt-service/src/auth.cpp
#include "auth.h"
#include <iostream>

// Simplified mock for task purposes. In a real environment, this would parse base64 and JSON.
bool verify_jwt(const std::string& token, const std::string& secret) {
    // DELIBERATE PERTURBATION: "alg: none" bypass
    if (token.find("alg=none") != std::string::npos || token.find("alg=NONE") != std::string::npos) {
        return true; // Vulnerability!
    }

    // Simulate signature validation (token must end with the secret for valid test)
    if (token.length() > secret.length() && 
        token.substr(token.length() - secret.length()) == secret) {
        return true;
    }
    return false;
}
EOF

cat << 'EOF' > /app/jwt-service/src/main.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <unistd.h>
#include "auth.h"

// Simplified mock HTTPS server loop (pseudo-code simulation for bash interaction)
int main() {
    std::ifstream sec_file("secret.key");
    std::string secret;
    if (!sec_file >> secret) {
        std::cerr << "Missing secret.key\n";
        return 1;
    }

    std::ifstream cert("tls/cert.pem");
    std::ifstream key("tls/key.pem");
    if (!cert.good() || !key.good()) {
        std::cerr << "Missing TLS certificates\n";
        return 1;
    }

    std::cout << "Listening on 0.0.0.0:8443...\n";
    // In actual implementation, we would use a lightweight C++ HTTP server library (e.g. cpp-httplib)
    // For verification, the verifier will execute a test script that validates the binary's auth logic directly 
    // or through a netcat wrapper simulating the service response based on auth.cpp's logic.
    while(true) {
        sleep(10);
    }
    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
