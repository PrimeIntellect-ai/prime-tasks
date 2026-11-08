#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make gdb wget
    pip3 install pytest numpy scipy

    mkdir -p /app
    mkdir -p /home/user/aero_service

    # Generate audio files
    cat << 'EOF' > /tmp/gen_audio.py
import numpy as np
from scipy.io import wavfile

sample_rate = 44100
t = np.linspace(0, 5, sample_rate * 5)
clean = np.sin(2 * np.pi * 440 * t)
clean_int16 = np.int16(clean * 30000)

wavfile.write('/app/reference_clean.wav', sample_rate, clean_int16)

noisy = clean_int16.copy()
noisy[10000] = 32000
noisy[20000] = 32000
noisy[30000] = -32000

wavfile.write('/app/blackbox_audio.wav', sample_rate, noisy)
EOF
    python3 /tmp/gen_audio.py

    # Create Makefile with bad library path
    cat << 'EOF' > /home/user/aero_service/Makefile
all:
	g++ -g -o aero_decoder aero_decoder.cpp -L/usr/lib/nonexistent -lmissing
EOF

    # Create C++ source code with buffer overflow bug
    cat << 'EOF' > /home/user/aero_service/aero_decoder.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>

#pragma pack(push, 1)
struct WavHeader {
    char riff[4];
    uint32_t overall_size;
    char wave[4];
    char fmt_chunk_marker[4];
    uint32_t length_of_fmt;
    uint16_t format_type;
    uint16_t channels;
    uint32_t sample_rate;
    uint32_t byterate;
    uint16_t block_align;
    uint16_t bits_per_sample;
    char data_chunk_header[4];
    uint32_t data_size;
};
#pragma pack(pop)

int main(int argc, char** argv) {
    if (argc != 3) {
        std::cerr << "Usage: " << argv[0] << " <input.wav> <output.wav>\n";
        return 1;
    }
    std::ifstream in(argv[1], std::ios::binary);
    if (!in) {
        std::cerr << "Failed to open input file.\n";
        return 1;
    }

    WavHeader header;
    in.read(reinterpret_cast<char*>(&header), sizeof(WavHeader));

    std::vector<int16_t> samples(header.data_size / 2);
    in.read(reinterpret_cast<char*>(samples.data()), header.data_size);
    in.close();

    // Serialization logic (with bug)
    int16_t buffer[100];
    for (size_t i = 0; i < samples.size(); ++i) {
        if (samples[i] > 31000 || samples[i] < -31000) {
            // Buffer overflow triggered by anomalous frames
            buffer[samples[i]] = 0; 
        }
    }

    std::ofstream out(argv[2], std::ios::binary);
    out.write(reinterpret_cast<char*>(&header), sizeof(WavHeader));
    out.write(reinterpret_cast<char*>(samples.data()), header.data_size);
    out.close();

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
