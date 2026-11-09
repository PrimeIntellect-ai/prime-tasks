#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg g++
pip3 install pytest

mkdir -p /app

# Generate the dummy video fixture quickly by applying geq only to the 100x100 region, then padding to 1920x1080
ffmpeg -f lavfi -i "color=c=black:s=100x100:r=1:d=30" -vf "geq=r='mod(T*20, 255)':g=0:b=0,pad=1920:1080:0:0:black" -pix_fmt yuv420p /app/dashboard_vnc.mp4 -y

# Compile the oracle
cat << 'EOF' > /app/oracle_extractor.cpp
#include <iostream>
#include <iomanip>
#include <cstdlib>
#include <cstdio>
#include <vector>

int main(int argc, char** argv) {
    if(argc != 2) return 1;
    int t = std::atoi(argv[1]);

    char cmd[256];
    snprintf(cmd, sizeof(cmd), "ffmpeg -ss %d -i /app/dashboard_vnc.mp4 -vframes 1 -f image2pipe -vcodec rawvideo -pix_fmt rgb24 - 2>/dev/null", t);

    FILE* pipe = popen(cmd, "r");
    if (!pipe) return 1;

    std::vector<unsigned char> buffer(1920 * 1080 * 3);
    fread(buffer.data(), 1, buffer.size(), pipe);
    pclose(pipe);

    double red_sum = 0;
    for(int y = 0; y < 100; ++y) {
        for(int x = 0; x < 100; ++x) {
            int idx = (y * 1920 + x) * 3;
            red_sum += buffer[idx];
        }
    }

    std::cout << std::fixed << std::setprecision(2) << (red_sum / 10000.0) << std::endl;
    return 0;
}
EOF

g++ /app/oracle_extractor.cpp -o /app/oracle_extractor
chmod +x /app/oracle_extractor

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
