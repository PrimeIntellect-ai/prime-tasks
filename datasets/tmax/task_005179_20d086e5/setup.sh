#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx g++ espeak ufw iptables
    pip3 install pytest

    # Create required directories
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate the audio memo
    espeak -w /app/voice_memo.wav "The Nginx upstream backend needs to be set to port 9337. Ensure port 9337 is blocked from the outside."

    # Populate the clean corpus
    cat << 'EOF' > /app/corpus/clean/1.json
{"user": "admin", "pass": "1234"}
EOF

    cat << 'EOF' > /app/corpus/clean/2.json
{"action": "ping", "timestamp": 1699999999}
EOF

    # Populate the evil corpus
    cat << 'EOF' > /app/corpus/evil/1.json
{"user": "admin", "pass": "1234'; DROP TABLE users;--"}
EOF

    cat << 'EOF' > /app/corpus/evil/2.json
{"cmd": "$(whoami)"}
EOF

    cat << 'EOF' > /app/corpus/evil/3.json
{"file": "../../../../etc/passwd"}
EOF

    # Create user
    useradd -m -s /bin/bash user || true

    # Create the C++ backend stub
    mkdir -p /home/user/backend
    cat << 'EOF' > /home/user/backend/server.cpp
#include <iostream>
#include <string>
#include <cstdlib>

int main() {
    std::string input;
    std::cin >> input;
    // Stub server - crashes on unexpected input
    std::cerr << "Fatal error: Unhandled input format." << std::endl;
    abort();
    return 0;
}
EOF

    # Ensure correct permissions
    chmod -R 777 /home/user
