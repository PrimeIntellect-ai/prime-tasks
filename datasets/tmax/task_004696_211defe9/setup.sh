#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make libssl-dev coreutils
    pip3 install pytest

    # Create vendored package directory
    mkdir -p /app/libauthtoken-1.2.0/src

    # Create Makefile missing -lcrypto
    cat << 'EOF' > /app/libauthtoken-1.2.0/Makefile
CXX = g++
CXXFLAGS = -Wall -Wextra -std=c++11
LDFLAGS = 

all: token_tool

token_tool: src/main.cpp src/validator.cpp
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS)

clean:
	rm -f token_tool
EOF

    # Create main.cpp
    cat << 'EOF' > /app/libauthtoken-1.2.0/src/main.cpp
#include <iostream>
#include <string>

bool validate_token(const std::string& token);

int main(int argc, char** argv) {
    if (argc < 3) return 1;
    std::string cmd = argv[1];
    std::string token = argv[2];
    if (cmd == "validate") {
        if (validate_token(token)) {
            std::cout << "VALID\n";
            return 0;
        } else {
            std::cout << "INVALID\n";
            return 1;
        }
    }
    return 1;
}
EOF

    # Create validator.cpp missing the overflow check
    cat << 'EOF' > /app/libauthtoken-1.2.0/src/validator.cpp
#include <string>
#include <iostream>
#include <openssl/sha.h>

void dummy_hash() {
    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256_CTX sha256;
    SHA256_Init(&sha256);
    SHA256_Update(&sha256, "test", 4);
    SHA256_Final(hash, &sha256);
}

bool validate_token(const std::string& token) {
    dummy_hash();
    size_t pos = token.find("\"exp\":");
    if (pos == std::string::npos) return false;

    size_t end_pos = token.find(",", pos);
    if (end_pos == std::string::npos) end_pos = token.find("}", pos);
    if (end_pos == std::string::npos) return false;

    std::string exp_str = token.substr(pos + 6, end_pos - pos - 6);
    long long exp_claim;
    try {
        exp_claim = std::stoll(exp_str);
    } catch (...) {
        return false;
    }

    // MISSING: if (exp_claim > 2147483647) { return false; }

    if (exp_claim < 0) return false;
    return true;
}
EOF

    # Create oracle
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/audit_wrapper_oracle
#!/bin/bash
# Oracle script
EOF
    chmod +x /opt/oracle/audit_wrapper_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
