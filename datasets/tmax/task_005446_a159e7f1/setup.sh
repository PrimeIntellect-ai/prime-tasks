#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/input.conf
app_name=frontend
replicas=3
EOF

cat << 'EOF' > /home/user/operator.cpp
#include <iostream>
#include <fstream>
#include <string>

int main() {
    std::ifstream infile("/home/user/input.conf");
    if (!infile.is_open()) {
        std::cerr << "Error reading input config" << std::endl;
        return 1;
    }

    std::string app_name = "unknown";
    std::string line;
    while (std::getline(infile, line)) {
        if (line.find("app_name=") == 0) {
            app_name = line.substr(9);
        }
    }

    std::ofstream outfile("/home/user/manifests/output.yaml");
    if (!outfile.is_open()) {
        std::cerr << "Error opening output file" << std::endl;
        return 1;
    }

    outfile << "apiVersion: v1\n";
    outfile << "kind: Pod\n";
    outfile << "metadata:\n";
    outfile << "  name: " << app_name << "\n";
    outfile << "spec:\n";
    // BUG IS HERE:
    outfile << "  upstreamSocket: /home/user/sockets/upstream.sock\n";

    outfile.close();
    return 0;
}
EOF

mkdir -p /home/user/manifests
touch /home/user/manifests/dummy1.txt
touch /home/user/manifests/dummy2.txt
touch /home/user/manifests/dummy3.bak
touch /home/user/manifests/dummy4.bak

chmod -R 777 /home/user
