#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/incident/bin

    # 1. Create upload_server.cpp
    cat << 'EOF' > /home/user/incident/upload_server.cpp
#include <iostream>
#include <string>

std::string handle_upload(const std::string& filename) {
    // Vulnerable path construction
    std::string filepath = "/var/www/uploads/" + filename;
    return "Uploading to: " + filepath;
}

int main() {
    std::cout << handle_upload("test.txt") << std::endl;
    return 0;
}
EOF

    # 2. Create tokens.txt
    cat << 'EOF' > /home/user/incident/tokens.txt
3b3633393f602f293f28
29232905327e223a28603b3e373334
383538602f293f28
EOF

    # 3. Create payload.b64
    cat << 'EOF' > /home/user/incident/payload.b64
Di4g0tzo0tz+HnEwbBDo1g==
EOF

    # 4. Create binaries and hashes
    echo "dummy cat content" > /home/user/incident/bin/cat
    echo "dummy ls content" > /home/user/incident/bin/ls
    echo "dummy ps content" > /home/user/incident/bin/ps
    echo "dummy grep content" > /home/user/incident/bin/grep

    # Calculate original hashes
    md5sum /home/user/incident/bin/cat | sed 's|/home/user/incident/bin/||' > /home/user/incident/hashes.md5
    md5sum /home/user/incident/bin/ls | sed 's|/home/user/incident/bin/||' >> /home/user/incident/hashes.md5
    md5sum /home/user/incident/bin/ps | sed 's|/home/user/incident/bin/||' >> /home/user/incident/hashes.md5
    md5sum /home/user/incident/bin/grep | sed 's|/home/user/incident/bin/||' >> /home/user/incident/hashes.md5

    # Modify the 'ps' binary to simulate compromise
    echo "malicious ps content" > /home/user/incident/bin/ps

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
