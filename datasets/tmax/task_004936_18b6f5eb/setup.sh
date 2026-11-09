#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ make
pip3 install pytest

mkdir -p /app/libdata-packer-1.0
cat << 'EOF' > /app/libdata-packer-1.0/Packer.h
#ifndef PACKER_H
#define PACKER_H
#include <string>
#include <vector>

class Packer {
public:
    Packer(const std::string& outputFile);
    ~Packer();
    void add_file(const std::string& path, const char* data, size_t size);
    void add_directory(const std::string& path);
    void save();
private:
    std::string outPath;
};
#endif
EOF

cat << 'EOF' > /app/libdata-packer-1.0/Packer.cpp
#include "Packer.h"
#include <fstream>
#include <filesystem>

Packer::Packer(const std::string& outputFile) : outPath(outputFile) {}
Packer::~Packer() {}

void Packer::add_file(const std::string& path, const char* data, size_t size) {
}

void Packer::add_directory(const std::string& path) {
    for (auto& entry : std::filesystem::recursive_directory_iterator(path, std::filesystem::directory_options::follow_directory_symlink)) {
    }
}

void Packer::save() {
}
EOF

mkdir -p /workspace/project_files

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
