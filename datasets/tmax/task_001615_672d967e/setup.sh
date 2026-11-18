#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-pil ffmpeg g++
    pip3 install pytest

    mkdir -p /app

    # Create oracle C++ source
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <string>
#include <map>
#include <fstream>
#include <sstream>

using namespace std;

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    int B = stoi(argv[1]);
    map<string, string> config;
    string line;
    while (getline(cin, line)) {
        stringstream ss(line);
        string cmd;
        ss >> cmd;
        if (cmd == "SET") {
            string k, v;
            ss >> k >> v;
            config[k] = v;
        } else if (cmd == "DEL") {
            string k;
            ss >> k;
            config.erase(k);
        } else if (cmd == "COMMIT") {
            string path;
            ss >> path;
            ofstream out(path, ios::binary);
            for (auto const& [k, v] : config) {
                string kv = k + "=" + v + "\n";
                for (char c : kv) {
                    out.put((char)((unsigned char)c + B));
                }
            }
        } else if (cmd == "LOAD") {
            string path;
            ss >> path;
            config.clear();
            ifstream in(path, ios::binary);
            if (!in) continue;
            string content;
            char c;
            while (in.get(c)) {
                content += (char)((unsigned char)c - B);
            }
            stringstream fss(content);
            string fline;
            while (getline(fss, fline)) {
                auto pos = fline.find('=');
                if (pos != string::npos) {
                    config[fline.substr(0, pos)] = fline.substr(pos + 1);
                }
            }
        } else if (cmd == "DUMP") {
            for (auto const& [k, v] : config) {
                cout << k << "=" << v << "\n";
            }
        }
    }
    return 0;
}
EOF

    g++ -O2 /app/oracle.cpp -o /app/oracle_config_manager
    strip /app/oracle_config_manager
    rm /app/oracle.cpp

    # Generate video with exactly 14 black frames
    cat << 'EOF' > /app/gen_video.py
import os
import subprocess
from PIL import Image

os.makedirs("/app/frames", exist_ok=True)
white = Image.new('RGB', (320, 240), color='white')
black = Image.new('RGB', (320, 240), color='black')

for i in range(150):
    if i < 14:
        black.save(f"/app/frames/frame_{i:03d}.png")
    else:
        white.save(f"/app/frames/frame_{i:03d}.png")

subprocess.run(["ffmpeg", "-y", "-framerate", "30", "-i", "/app/frames/frame_%03d.png", "-c:v", "libx264", "-pix_fmt", "yuv420p", "/app/server_logs.mp4"], check=True)
EOF
    python3 /app/gen_video.py
    rm -rf /app/frames /app/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
