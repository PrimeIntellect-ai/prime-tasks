#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ libssl-dev openssh-client
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/.ssh

cat << 'EOF' > /home/user/access.log
192.168.1.50 - - [10/Oct/2023:13:55:36 +0000] "GET /login?redirect=/dashboard HTTP/1.1" 200 1024
10.0.0.12 - - [10/Oct/2023:13:56:10 +0000] "GET /login?redirect=http://malicious.com/steal HTTP/1.1" 302 512
192.168.1.100 - - [10/Oct/2023:13:58:22 +0000] "GET /login?redirect=/profile HTTP/1.1" 200 1040
172.16.5.5 - - [10/Oct/2023:14:01:05 +0000] "GET /login?redirect=https://evil.org/phish HTTP/1.1" 302 512
10.0.0.15 - - [10/Oct/2023:14:05:00 +0000] "GET /about HTTP/1.1" 200 2048
EOF

cat << 'EOF' > /home/user/audit_scanner.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <regex>

// TODO: Include OpenSSL headers for SHA256

std::string compute_sha256(const std::string& input) {
    // TODO: Implement SHA-256 hashing using OpenSSL returning lowercase hex string
    return "unimplemented_hash";
}

int main() {
    std::ifstream file("/home/user/access.log");
    std::string line;
    std::regex log_regex(R"(^(\S+).*"GET /login\?redirect=([^ ]+) HTTP.*)");
    std::smatch match;

    while (std::getline(file, line)) {
        if (std::regex_search(line, match, log_regex)) {
            std::string ip = match[1].str();
            std::string redirect_url = match[2].str();

            // BUG: Currently flags all redirects. Add condition to check for http:// or https://

            std::cout << ip << "," << redirect_url << "," << compute_sha256(redirect_url) << std::endl;
        }
    }
    return 0;
}
EOF

chown -R user:user /home/user
chmod -R 777 /home/user
