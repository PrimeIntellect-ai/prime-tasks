#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.ssh
    chmod 700 /home/user/.ssh

    cat << 'EOF' > /home/user/.ssh/authorized_keys
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAaXb... user1@domain
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC... user2@domain
ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAA... user3@domain
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC... attacker@domain
EOF
    chmod 600 /home/user/.ssh/authorized_keys

    cat << 'EOF' > /home/user/upload_server.cpp
#include <iostream>
#include <string>
#include <fstream>

void save_uploaded_file(std::string filename) {
    std::string path = "/var/uploads/" + filename;
    std::ofstream out(path);
    out << "data";
    out.close();
}

int main() {
    save_uploaded_file("test.txt");
    return 0;
}
EOF

    chmod -R 777 /home/user
