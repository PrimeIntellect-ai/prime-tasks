#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ ffmpeg
    pip3 install pytest gTTS

    mkdir -p /app
    mkdir -p /home/user/data

    # Generate the audio file
    cat << 'EOF' > /app/generate_audio.py
from gtts import gTTS
import os

text = "Hey, it's Alex. The analyzer is failing on the new x86 servers. It's overflowing because the total payload accumulator is a 32-bit signed integer, but we process over 3 gigabytes of data now; change it to a 64-bit unsigned int. Also, there's a corrupted input issue: any packet header starting with the byte 0xFF is corrupted and must be completely skipped, but the current code misaligns the file pointer by not advancing past the 4-byte payload size of corrupted packets. Finally, the sequence numbers are strictly less than 65536, watch out for the off-by-one error in the boundary check."

tts = gTTS(text)
tts.save("/app/ticket_0042.mp3")
os.system("ffmpeg -i /app/ticket_0042.mp3 /app/ticket_0042.wav -y 2>/dev/null")
EOF
    python3 /app/generate_audio.py
    rm /app/generate_audio.py /app/ticket_0042.mp3

    # Generate the binary data file
    cat << 'EOF' > /app/generate_data.py
import struct

with open('/home/user/data/network_log.dat', 'wb') as f:
    # 1000 valid packets
    for i in range(1000):
        f.write(struct.pack('<BHI', 1, i, 3500000))

    # 1 corrupted packet
    f.write(struct.pack('<BHI', 0xFF, 1000, 0))

    # 1000 valid packets
    for i in range(1001, 2001):
        f.write(struct.pack('<BHI', 1, i, 3500000))
EOF
    python3 /app/generate_data.py
    rm /app/generate_data.py

    # Create the buggy C++ code
    cat << 'EOF' > /home/user/analyzer.cpp
#include <iostream>
#include <fstream>
#include <cstdint>

int main() {
    std::ifstream file("/home/user/data/network_log.dat", std::ios::binary);
    if (!file) {
        std::cerr << "Failed to open data file.\n";
        return 1;
    }

    int32_t total_payload = 0;
    int valid_packets = 0;

    while (true) {
        uint8_t type;
        if (!file.read(reinterpret_cast<char*>(&type), 1)) break;

        uint16_t seq;
        file.read(reinterpret_cast<char*>(&seq), 2);

        if (type == 0xFF) {
            // Corrupted packet, skip it
            continue;
        }

        uint32_t payload_size;
        file.read(reinterpret_cast<char*>(&payload_size), 4);

        if (seq <= 65536) {
            total_payload += payload_size;
            valid_packets++;
        }
    }

    std::ofstream out("/home/user/summary.txt");
    if (valid_packets > 0) {
        out << (double)total_payload / valid_packets << "\n";
    } else {
        out << 0.0 << "\n";
    }
    out << valid_packets << "\n";

    return 0;
}
EOF

    # Create the golden summary
    cat << 'EOF' > /app/golden_summary.txt
3500000.0
2000
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
