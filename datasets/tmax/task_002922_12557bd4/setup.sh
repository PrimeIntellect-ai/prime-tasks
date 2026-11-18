#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libssl-dev nlohmann-json3-dev openssh-client espeak
    pip3 install pytest

    mkdir -p /app

    # Generate encrypted SSH key
    ssh-keygen -t rsa -b 2048 -N "atd97" -f /app/compromised_id_rsa

    # Generate audio file
    espeak -w /app/intercept.wav "The passphrase for the exfiltration key is alpha tango delta niner seven."

    # Create dummy auth_daemon binary
    cat << 'EOF' > /tmp/auth_daemon.cpp
#include <iostream>
int main() {
    std::cout << "Auth Daemon" << std::endl;
    return 0;
}
EOF
    g++ /tmp/auth_daemon.cpp -o /app/auth_daemon
    rm /tmp/auth_daemon.cpp

    # Create corpora directories
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Populate evil corpus
    cat << 'EOF' > /app/corpora/evil/payload1.json
{"cmd_exec": "ls ; rev", "user_profile_xss": "<script>alert('XSS')</script>"}
EOF
    cat << 'EOF' > /app/corpora/evil/payload2.json
{"cmd_exec": "echo test | bash", "user_profile_xss": "javascript:eval('malicious')"}
EOF

    # Populate clean corpus
    cat << 'EOF' > /app/corpora/clean/payload1.json
{"cmd_exec": "echo hello", "user_profile_xss": "Alice"}
EOF
    cat << 'EOF' > /app/corpora/clean/payload2.json
{"cmd_exec": "uptime", "user_profile_xss": "Bob"}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
