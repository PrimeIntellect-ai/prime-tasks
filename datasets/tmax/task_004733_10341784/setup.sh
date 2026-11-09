#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ make
    pip3 install pytest

    mkdir -p /app/audio
    mkdir -p /home/user

    # Generate input.wav
    cat << 'EOF' > /tmp/gen_audio.py
import wave
import struct
import math

sample_rate = 16000
num_samples = 16000 * 5 # 5 seconds

with wave.open('/app/audio/input.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(sample_rate)
    for i in range(num_samples):
        # Generate some signal with varying amplitude to trigger variance instability
        t = i / sample_rate
        val = math.sin(2 * math.pi * 440 * t) * 10000 + 15000
        data = struct.pack('<h', int(max(-32768, min(32767, val))))
        f.writeframesraw(data)
EOF
    python3 /tmp/gen_audio.py

    # Create libfilter.so
    cat << 'EOF' > /tmp/filter.c
const float taps_array[8] = {0.11f, 0.22f, 0.33f, 0.15f, -0.05f, -0.12f, -0.20f, -0.04f};
EOF
    gcc -shared -fPIC /tmp/filter.c -o /home/user/libfilter.so

    # Create the buggy processor.cpp
    cat << 'EOF' > /home/user/processor.cpp
#include <iostream>
#include <vector>
#include <thread>
#include <cmath>
#include <fstream>
#include <cstdint>

#pragma pack(push, 1)
struct WavHeader {
    char riff[4] = {'R','I','F','F'};
    uint32_t fileSize;
    char wave[4] = {'W','A','V','E'};
    char fmt[4] = {'f','m','t',' '};
    uint32_t fmtSize = 16;
    uint16_t audioFormat = 1;
    uint16_t numChannels = 1;
    uint32_t sampleRate = 16000;
    uint32_t byteRate = 32000;
    uint16_t blockAlign = 2;
    uint16_t bitsPerSample = 16;
    char data[4] = {'d','a','t','a'};
    uint32_t dataSize;
};
#pragma pack(pop)

const int BLOCK_SIZE = 1000;

// TODO: Replace with correct taps from libfilter.so
const float TAPS[8] = {1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f};

void process_block(const std::vector<int16_t>& input, std::vector<int16_t>& output, int block_idx) {
    int start = block_idx * BLOCK_SIZE;
    int end = std::min(start + BLOCK_SIZE, (int)input.size());
    int n = end - start;
    if (n <= 0) return;

    // Numerical instability: Naive variance
    float sum = 0;
    float sum_sq = 0;
    for (int i = start; i < end; ++i) {
        float val = input[i];
        sum += val;
        sum_sq += val * val;
    }

    float mean = sum / n;
    float variance = (sum_sq - (sum * sum) / n) / n;

    // Protect against negative variance from catastrophic cancellation, but it might already be NaN
    float stddev = std::sqrt(std::max(0.0001f, variance)); 

    std::vector<float> norm_buffer(n);
    for (int i = 0; i < n; ++i) {
        norm_buffer[i] = (input[start + i] - mean) / stddev;
    }

    // Apply FIR filter
    for (int i = 0; i < n; ++i) {
        float out_val = 0;
        for (int j = 0; j < 8; ++j) {
            if (i - j >= 0) {
                out_val += norm_buffer[i - j] * TAPS[j];
            }
        }
        // Denormalize and scale
        float final_val = (out_val * stddev) + mean;
        output[start + i] = std::max(-32768.0f, std::min(32767.0f, final_val));
    }
}

int main(int argc, char** argv) {
    if (argc < 3) return 1;

    std::ifstream in(argv[1], std::ios::binary);
    WavHeader header;
    in.read(reinterpret_cast<char*>(&header), sizeof(header));

    int num_samples = header.dataSize / 2;
    std::vector<int16_t> input(num_samples);
    in.read(reinterpret_cast<char*>(input.data()), header.dataSize);
    in.close();

    std::vector<int16_t> output(num_samples, 0);
    int num_blocks = (num_samples + BLOCK_SIZE - 1) / BLOCK_SIZE;
    std::vector<std::thread> threads;

    // Concurrency Bug: capturing 'i' by reference causes a race condition
    for (int i = 0; i < num_blocks; ++i) {
        threads.push_back(std::thread([&, i]() {
            // Wait, capturing i by value is correct. 
            // Let's introduce the bug: capturing i by reference
        }));
    }
    // Real buggy loop:
    for (int i = 0; i < num_blocks; ++i) {
        threads.push_back(std::thread([&]() {
            process_block(input, output, i);
        }));
    }

    for (auto& t : threads) {
        t.join();
    }

    std::ofstream out(argv[2], std::ios::binary);
    out.write(reinterpret_cast<char*>(&header), sizeof(header));
    out.write(reinterpret_cast<char*>(output.data()), header.dataSize);
    out.close();

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user
    chmod -R 777 /app
