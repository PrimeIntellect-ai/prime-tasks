#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /home/user

    # Create auth_service.cpp
    cat << 'EOF' > /tmp/auth_service.cpp
#include <cstdlib>
#include <ctime>
#include <iostream>

namespace Auth {
    bool verify_token(int id, const char* token);
}

int main() {
    std::srand(std::time(nullptr));
    // Fails intermittently (1 in 5 chance)
    int id = std::rand() % 5;
    if (!Auth::verify_token(id, "secret_token")) {
        return 1; // Crash
    }
    return 0; // Success
}
EOF

    # Create dummy library and compile auth_service
    cat << 'EOF' > /tmp/dummy.cpp
namespace Auth { bool verify_token(int id, const char* token) { return true; } }
EOF
    cd /tmp
    g++ -shared -fPIC dummy.cpp -o libauth.so
    g++ auth_service.cpp -o /home/user/auth_service -L. -lauth -Wl,-rpath=/home/user
    rm dummy.cpp libauth.so auth_service.cpp

    # Create the embedded text for disk_image.bin
    cat << 'EOF' > /tmp/broken_auth.cpp
// AUTH_MODULE_START
#include <iostream>

namespace Authentication {
    bool verify_token(int id, const char* token) {
        if (id == 0) return false;
        return true;
    }
}
// AUTH_MODULE_END
EOF

    # Generate /home/user/disk_image.bin
    dd if=/dev/urandom of=/home/user/disk_image.bin bs=1M count=2
    cat /tmp/broken_auth.cpp >> /home/user/disk_image.bin
    dd if=/dev/urandom >> /home/user/disk_image.bin bs=1M count=2
    rm /tmp/broken_auth.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
