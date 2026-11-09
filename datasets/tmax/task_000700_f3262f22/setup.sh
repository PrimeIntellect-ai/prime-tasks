#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr g++
    pip3 install pytest

    mkdir -p /app

    # Create the screenshot
    convert -size 400x100 xc:white -pointsize 24 -fill black -draw "text 10,50 'AdminPass: KiloTango'" +noise Gaussian /app/creds_screenshot.png

    # Create the legacy hash C++ file
    cat << 'EOF' > /app/legacy_hash.cpp
#include <string>
#include <chrono>
#include <thread>

// Deliberately slow hash function
unsigned int legacy_hash(const std::string& input) {
    unsigned int hash = 0;
    for (char c : input) {
        hash += c;
        // Redundant slow loop
        for(int i=0; i<10000; ++i) {
            hash ^= i;
            hash ^= i;
        }
    }
    return hash;
}
EOF

    # Calculate the hash for "KiloTangowxyz" to put in the logs
    cat << 'EOF' > /tmp/gen_hash.cpp
#include <iostream>
#include <string>

unsigned int legacy_hash(const std::string& input) {
    unsigned int hash = 0;
    for (char c : input) {
        hash += c;
        for(int i=0; i<10000; ++i) {
            hash ^= i;
            hash ^= i;
        }
    }
    return hash;
}

int main() {
    std::cout << legacy_hash("KiloTangowxyz") << std::endl;
    return 0;
}
EOF
    g++ -o /tmp/gen_hash /tmp/gen_hash.cpp
    TARGET_HASH=$(/tmp/gen_hash)

    # Create the auth logs
    cat << EOF > /app/auth_logs.txt
[INFO] System startup
[ERROR] Failed login for 'admin'. Supplied hash: ${TARGET_HASH}
EOF

    # Create the vault CLI
    cat << 'EOF' > /app/vault_cli.cpp
#include <iostream>
#include <string>
int main(int argc, char** argv) {
    std::string pass = "";
    for(int i=1; i<argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--pass" && i+1 < argc) pass = argv[i+1];
    }
    if (pass == "KiloTangowxyz") {
        std::cout << "Success\n";
        return 0;
    }
    std::cout << "Failed\n";
    return 1;
}
EOF
    g++ -o /app/vault_cli /app/vault_cli.cpp
    chmod +x /app/vault_cli

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
