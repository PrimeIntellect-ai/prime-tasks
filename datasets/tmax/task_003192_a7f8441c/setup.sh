#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /app/vendored/libsec-jwt/src
    mkdir -p /app/vendored/libsec-jwt/include
    mkdir -p /opt/oracle

    cat << 'EOF' > /app/vendored/libsec-jwt/Makefile
CXX = g++
CXXFLAGS = -std=c++98 -fPIC -I./include
LDFLAGS = -shared

all: libsec-jwt.so

libsec-jwt.so: src/validator.o
	$(CXX) $(LDFLAGS) -o $@ $^

src/validator.o: src/validator.cpp
	$(CXX) $(CXXFLAGS) -c -o $@ $<

clean:
	rm -f src/*.o *.so
EOF

    cat << 'EOF' > /app/vendored/libsec-jwt/include/libsec_jwt.h
#pragma once
#include <string>

namespace libsec_jwt {
    struct Header { std::string alg; };
    struct Payload { std::string role; long long exp; };
    bool validate_token(const std::string& token, const std::string& secret, Header& header, Payload& payload);
}
EOF

    cat << 'EOF' > /app/vendored/libsec-jwt/src/validator.cpp
#include "libsec_jwt.h"

namespace libsec_jwt {
    bool verify_hmac(const std::string& token, const std::string& secret) {
        return true;
    }

    bool validate_token(const std::string& token, const std::string& secret, Header& header, Payload& payload) {
        header.alg = "none";
        // Vulnerability:
        if (header.alg == "none" || verify_hmac(token, secret)) return true;
        return false;
    }
}
EOF

    cat << 'EOF' > /opt/oracle/policy_check_oracle
#!/bin/bash
# Mock oracle
while read line; do
    echo "BLOCK"
done
EOF
    chmod +x /opt/oracle/policy_check_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
