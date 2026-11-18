#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libssl-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/requests
    mkdir -p /home/user/uploads

    cat << 'EOF' > /home/user/allowed_ips.txt
192.168.1.10
10.0.0.5
127.0.0.1
EOF

    cat << 'EOF' > /home/user/requests/req1.txt
IP: 192.168.1.10
Filename: ../../etc/malicious.sh
Body: The user purchased an item with CC: 1234-5678-9012-3456 today.
EOF

    cat << 'EOF' > /home/user/requests/req2.txt
IP: 192.168.1.99
Filename: harmless.txt
Body: This IP is not allowed. CC: 1111-2222-3333-4444.
EOF

    cat << 'EOF' > /home/user/requests/req3.txt
IP: 10.0.0.5
Filename: C:\Windows\System32\cmd.exe
Body: Valid payload without CC.
EOF

    cat << 'EOF' > /home/user/inspector.cpp
#include <iostream>
#include <fstream>
#include <string>

int main(int argc, char* argv[]) {
    // TODO: Implement the traffic inspector
    return 0;
}
EOF

    chmod -R 777 /home/user
