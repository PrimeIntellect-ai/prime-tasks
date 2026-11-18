#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/storage_pool/projectA
    mkdir -p /home/user/storage_pool/projectB

    cat << 'EOF' > /home/user/storage_pool/projectA/main.cpp.old_backup
#include <iostream>
// TODO: STORAGE_QUOTA
int main() {
    return 0;
}
EOF

    cat << 'EOF' > /home/user/storage_pool/projectB/utils.cpp.old_backup
// TODO: STORAGE_QUOTA
// Just a utility file
void do_nothing() {}
EOF

    cat << 'EOF' > /home/user/storage_pool/projectB/data.cpp.old_backup
// No quota here
int data = 42;
EOF

    ln -s /home/user/storage_pool /home/user/storage_pool/projectA/loop_dir

    cat << 'EOF' > /home/user/indexer.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <unistd.h>
#include <fcntl.h>
// MISSING: include for flock

int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <manifest_file>\n";
        return 1;
    }

    std::ifstream manifest(argv[1]);
    int count = 0;
    std::string line;
    while (std::getline(manifest, line)) {
        if (!line.empty()) count++;
    }

    int fd = open("/home/user/storage_report.log", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return 1;

    // flock requires the missing header
    if (flock(fd, LOCK_EX) == -1) {
        return 1;
    }

    std::string output = "Total verified files: " + std::to_string(count) + "\n";
    write(fd, output.c_str(), output.length());

    flock(fd, LOCK_UN);
    close(fd);

    return 0;
}
EOF

    chmod -R 777 /home/user
