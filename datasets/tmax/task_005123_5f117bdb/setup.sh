#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ valgrind
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project_sync/data

    # Create data files
    echo -n "Hello CI/CD Pipeline!" > /home/user/project_sync/data/file1.txt
    echo -n "Memory safety is important." > /home/user/project_sync/data/file2.txt
    echo -n "REST API Payload Test" > /home/user/project_sync/data/file3.txt

    # Create reference python script
    cat << 'EOF' > /home/user/project_sync/checksum_ref.py
import os
import json

def fletcher16(data):
    sum1 = 0
    sum2 = 0
    for byte in data:
        sum1 = (sum1 + byte) % 255
        sum2 = (sum2 + sum1) % 255
    return (sum2 << 8) | sum1

def process_directory(dir_path):
    results = {}
    for f in sorted(os.listdir(dir_path)):
        with open(os.path.join(dir_path, f), 'rb') as fp:
            data = fp.read()
            results[f] = fletcher16(data)

    payload = {"files": results}
    with open('/home/user/project_sync/api_payload.json', 'w') as out:
        json.dump(payload, out, indent=2)

if __name__ == '__main__':
    process_directory('/home/user/project_sync/data')
EOF

    # Create buggy C++ script
    cat << 'EOF' > /home/user/project_sync/fast_checksum.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <dirent.h>
#include <algorithm>
#include <iomanip>

uint16_t fletcher16(const uint8_t* data, size_t len) {
    uint16_t sum1 = 0;
    uint16_t sum2 = 0;
    // BUG: <= len causes buffer overflow (Undefined Behavior)
    for (size_t i = 0; i <= len; ++i) {
        sum1 = (sum1 + data[i]) % 255;
        sum2 = (sum2 + sum1) % 255;
    }
    return (sum2 << 8) | sum1;
}

int main() {
    std::string dir_path = "/home/user/project_sync/data";
    DIR *dir;
    struct dirent *ent;
    std::vector<std::string> files;

    if ((dir = opendir(dir_path.c_str())) != NULL) {
        while ((ent = readdir(dir)) != NULL) {
            std::string fname = ent->d_name;
            if (fname != "." && fname != "..") {
                files.push_back(fname);
            }
        }
        closedir(dir);
    }

    std::sort(files.begin(), files.end());

    std::ofstream out("/home/user/project_sync/api_payload.json");
    out << "{\n  \"files\": {\n";

    for (size_t i = 0; i < files.size(); ++i) {
        std::string full_path = dir_path + "/" + files[i];
        std::ifstream file(full_path, std::ios::binary | std::ios::ate);
        std::streamsize size = file.tellg();
        file.seekg(0, std::ios::beg);

        // BUG: Memory leak (no delete[])
        char* buffer = new char[size];
        if (file.read(buffer, size)) {
            uint16_t checksum = fletcher16(reinterpret_cast<const uint8_t*>(buffer), size);
            out << "    \"" << files[i] << "\": " << checksum;
            if (i < files.size() - 1) out << ",";
            out << "\n";
        }
    }
    out << "  }\n}\n";
    out.close();
    return 0;
}
EOF

    chmod -R 777 /home/user
