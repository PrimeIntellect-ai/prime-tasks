#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

mkdir -p /app
dd if=/dev/urandom of=/app/dataset_stream.raw bs=1M count=105
chmod 644 /app/dataset_stream.raw

cat << 'EOF' > /app/ref_tool.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <sstream>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <cmath>

int main() {
    const char* filepath = "/app/dataset_stream.raw";
    int fd = open(filepath, O_RDONLY);
    if (fd < 0) return 1;
    struct stat st;
    fstat(fd, &st);
    int16_t* map = (int16_t*)mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);

    std::string line;
    while (std::getline(std::cin, line)) {
        std::istringstream iss(line);
        std::string cmd, out_path;
        size_t offset, length;
        float scale;
        if (!(iss >> cmd >> offset >> length >> scale >> out_path)) continue;
        if (cmd != "extract") continue;

        std::string tmp_path = out_path + ".tmp";
        std::ofstream out(tmp_path, std::ios::binary);

        size_t start_idx = offset / 2;
        size_t num_samples = length / 2;
        for (size_t i = 0; i < num_samples; ++i) {
            float val = map[start_idx + i] * scale;
            if (val > 32767.0f) val = 32767.0f;
            if (val < -32768.0f) val = -32768.0f;
            int16_t out_val = static_cast<int16_t>(std::round(val));
            out.write(reinterpret_cast<const char*>(&out_val), sizeof(int16_t));
        }
        out.close();
        rename(tmp_path.c_str(), out_path.c_str());
        std::cout << "DONE " << out_path << std::endl;
    }
    return 0;
}
EOF

g++ -O3 /app/ref_tool.cpp -o /app/ref_tool
chmod +x /app/ref_tool

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
