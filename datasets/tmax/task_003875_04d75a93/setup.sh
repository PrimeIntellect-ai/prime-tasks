#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/hash_impl.cpp
#include <iostream>
#include <string>
#include <iomanip>

// Proprietary 32-bit Hash Implementation (FNV-1a variant)
unsigned int compute_hash(const std::string& password) {
    unsigned int hash = 0x811c9dc5;
    for (char c : password) {
        hash ^= static_cast<unsigned char>(c);
        hash *= 0x01000193;
    }
    return hash;
}

/* Example usage:
int main() {
    std::cout << std::hex << compute_hash("test") << std::endl;
    return 0;
}
*/
EOF

    cat << 'EOF' > /home/user/compromised_accounts.txt
alice:d09a3410
bob:1e3f8a00
charlie:8bf8f47d
diana:717c1407
eve:c9842a27
EOF

    chmod -R 777 /home/user
