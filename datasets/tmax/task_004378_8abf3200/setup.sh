#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        build-essential \
        espeak \
        time

    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/audio_processor

    # Generate audio file
    espeak -w /app/config.wav "The threshold value is forty two"

    # Generate dataset
    cat << 'EOF' > /app/generate_data.py
import struct
import random

# Generate 50MB of DataRecord structs
# struct DataRecord { int id; float value; char padding[4]; }; -> 12 bytes
# 50MB / 12 bytes ~= 4,166,666 records
num_records = 4166666
with open('/app/dataset.bin', 'wb') as f:
    for i in range(num_records):
        val = random.uniform(0.0, 100.0)
        f.write(struct.pack('if4s', i, val, b'pad\0'))
EOF
    python3 /app/generate_data.py
    rm /app/generate_data.py

    # Create project files
    cat << 'EOF' > /home/user/audio_processor/legacy_io.h
#ifndef LEGACY_IO_H
#define LEGACY_IO_H

#include <stdio.h>

struct DataRecord {
    int id;
    float value;
    char padding[4];
};

int read_records(const char* filename, struct DataRecord** records, int* count);

#endif
EOF

    cat << 'EOF' > /home/user/audio_processor/legacy_io.c
#include "legacy_io.h"
#include <stdlib.h>

int read_records(const char* filename, struct DataRecord** records, int* count) {
    FILE* f = fopen(filename, "rb");
    if (!f) return -1;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    *count = size / sizeof(struct DataRecord);
    *records = (struct DataRecord*)malloc(size);
    fread(*records, sizeof(struct DataRecord), *count, f);
    fclose(f);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/audio_processor/main.cpp
#include <iostream>
#include <vector>

// Intentional missing extern "C"
#include "legacy_io.h"

void process_records(struct DataRecord* records, int count, const char* out_filename);

int main(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "Usage: " << argv[0] << " <input.bin> <output.bin>\n";
        return 1;
    }
    struct DataRecord* records = nullptr;
    int count = 0;
    if (read_records(argv[1], &records, &count) != 0) {
        std::cerr << "Failed to read records.\n";
        return 1;
    }
    process_records(records, count, argv[2]);
    free(records);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/audio_processor/processor.cpp
#include <iostream>
#include <vector>
#include <fstream>

// Intentional missing extern "C"
#include "legacy_io.h"

float THRESHOLD = 0.0; // Hardcode threshold here

void process_records(struct DataRecord* records, int count, const char* out_filename) {
    std::vector<struct DataRecord> filtered;
    for (int i = 0; i < count; ++i) {
        if (records[i].value > THRESHOLD) {
            filtered.push_back(records[i]);
        }
    }

    // Naive bubble sort (intentionally slow)
    for (size_t i = 0; i < filtered.size(); ++i) {
        for (size_t j = 0; j < filtered.size() - 1; ++j) {
            if (filtered[j].value < filtered[j+1].value) {
                struct DataRecord temp = filtered[j];
                filtered[j] = filtered[j+1];
                filtered[j+1] = temp;
            }
        }
    }

    std::ofstream out(out_filename, std::ios::binary);
    for (const auto& r : filtered) {
        out.write(reinterpret_cast<const char*>(&r), sizeof(struct DataRecord));
    }
}
EOF

    cat << 'EOF' > /home/user/audio_processor/Makefile
CXX = g++
CC = gcc
CXXFLAGS = -O3 -Wall
CFLAGS = -O3 -Wall

all: build/audio_processor

build/audio_processor: build/main.o build/processor.o build/legacy_io.o
	@mkdir -p build
	$(CXX) $(CXXFLAGS) -o $@ $^

build/%.o: %.cpp
	@mkdir -p build
	$(CXX) $(CXXFLAGS) -c $< -o $@

build/%.o: %.c
	@mkdir -p build
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -rf build
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
