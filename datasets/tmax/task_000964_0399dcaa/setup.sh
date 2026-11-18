#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ ffmpeg
pip3 install pytest

mkdir -p /app

# Generate a dummy audio file for testing
python3 -c "
import wave, struct
with wave.open('/app/interview.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(16000)
    for i in range(16000):
        f.writeframesraw(struct.pack('<h', 0))
"

# Generate the oracle executable for fuzzing
cat << 'EOF' > /app/oracle_extractor.cpp
#include <iostream>
#include <vector>
#include <cstdint>

int main() {
    std::vector<int16_t> samples;
    int16_t val;
    while (std::cin >> val) {
        samples.push_back(val);
    }

    int W = 256;
    int S = 128;
    std::vector<long long> outputs;

    for (size_t i = 0; i + W <= samples.size(); i += S) {
        long long E = 0;
        for (int j = 0; j < W - 1; ++j) {
            long long diff = (long long)samples[i + j + 1] - (long long)samples[i + j];
            E += diff * diff;
        }
        long long E_mod = (E * 137LL) % 999983LL;
        outputs.push_back(E_mod);
    }

    for (size_t i = 0; i < outputs.size(); ++i) {
        std::cout << outputs[i] << (i == outputs.size() - 1 ? "" : " ");
    }
    std::cout << "\n";
    return 0;
}
EOF

g++ -O3 /app/oracle_extractor.cpp -o /app/oracle_extractor
chmod +x /app/oracle_extractor

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
