#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gdb wget
    pip3 install pytest numpy scipy

    mkdir -p /app

    cat << 'EOF' > /app/encoder.cpp
#include <iostream>
#include <fstream>
#include <vector>

struct AudioChunk {
    size_t size;
    char* data; // BUG 1: Serialization writes the pointer, not the data
};

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    std::ifstream in(argv[1], std::ios::binary);
    std::ofstream out(argv[2], std::ios::binary);

    in.seekg(0, std::ios::end);
    size_t fileSize = in.tellg();
    in.seekg(0, std::ios::beg);

    std::vector<char> buffer(fileSize);
    in.read(buffer.data(), fileSize);

    AudioChunk chunk;
    chunk.size = fileSize;
    chunk.data = buffer.data();

    // BUG 1: Writes the struct literally, meaning the pointer address is written instead of the buffer content
    out.write(reinterpret_cast<char*>(&chunk.size), sizeof(chunk.size));
    out.write(reinterpret_cast<char*>(&chunk.data), sizeof(chunk.data)); 
    // Fix should be: out.write(chunk.data, chunk.size);

    return 0;
}
EOF

    cat << 'EOF' > /app/decoder.cpp
#include <iostream>
#include <fstream>
#include <vector>
// BUG 2: Missing <cstdint> causing build failure if uint64_t is used
// BUG 3: Missing <cstring>

struct AudioChunk {
    size_t size;
    char* data;
};

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    std::ifstream in(argv[1], std::ios::binary);
    std::ofstream out(argv[2], std::ios::binary);

    size_t size;
    in.read(reinterpret_cast<char*>(&size), sizeof(size));

    // BUG 4: Segfault/buffer overflow risk here due to reading pointer from the broken encoder
    // If the encoder is broken, 'size' might be garbage. If encoder is fixed, this logic still needs to read the data correctly.
    char* junk_ptr;
    in.read(reinterpret_cast<char*>(&junk_ptr), sizeof(char*)); // Reads the bad pointer

    // Fix: The decoder should be rewritten to just read 'size' bytes directly into a vector and write to 'out'.
    std::vector<char> buffer(size);
    // When encoder is fixed, the decoder should just read: in.read(buffer.data(), size);

    // Intentional crash if not fixed:
    buffer[size + 1000] = 'X'; 

    out.write(buffer.data(), size);
    return 0;
}
EOF

    # Generate a simple valid WAV file for testing
    python3 -c "
import numpy as np
from scipy.io import wavfile
sample_rate = 44100
t = np.linspace(0, 1, sample_rate, False)
note = np.sin(2 * np.pi * 440 * t)
audio = np.int16(note * 32767)
wavfile.write('/app/suspicious_payload.wav', sample_rate, audio)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
