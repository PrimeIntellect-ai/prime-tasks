#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ python3-pil
    pip3 install --default-timeout=100 pytest

    mkdir -p /home/user/telemetry_classifier/src
    mkdir -p /home/user/telemetry_classifier/bin
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    cat << 'EOF' > /home/user/telemetry_classifier/build.sh
#!/bin/bash
mkdir -p bin
for f in $(ls src/*.cpp); do
    g++ -c $f -o bin/$(basename $f .cpp).o
done
g++ bin/*.o -o bin/classifier
EOF
    chmod +x /home/user/telemetry_classifier/build.sh

    cat << 'EOF' > /home/user/telemetry_classifier/src/classifier.cpp
#include <iostream>
#include <fstream>
#include <vector>

#define THRESHOLD 0.00

extern std::vector<float> parse_data(const std::string& filename);

float calculate_score(const std::vector<float>& data) {
    float total_score; // Bug: uninitialized variable
    for (float val : data) {
        total_score += val;
    }
    return total_score;
}

int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <file_path>\n";
        return 1;
    }
    std::vector<float> data = parse_data(argv[1]);
    float score = calculate_score(data);
    if (score >= THRESHOLD) {
        std::cout << "EVIL\n";
    } else {
        std::cout << "CLEAN\n";
    }
    return 0;
}
EOF

    cat << 'EOF' > "/home/user/telemetry_classifier/src/data parser.cpp"
#include <string>
#include <vector>
#include <fstream>

std::vector<float> parse_data(const std::string& filename) {
    std::vector<float> data;
    std::ifstream file(filename);
    float val;
    while (file >> val) {
        data.push_back(val);
    }
    return data;
}
EOF

    # Generate image and corpora
    python3 -c '
from PIL import Image, ImageDraw
img = Image.new("RGB", (200, 50), color = (73, 109, 137))
d = ImageDraw.Draw(img)
d.text((10,10), "THRESHOLD=42.73", fill=(255,255,0))
img.save("/app/malware_seed.png")

import os
# Evil corpus (sum >= 42.73)
for i in range(5):
    with open(f"/app/corpora/evil/payload_{i}.txt", "w") as f:
        f.write("20.0 10.0 15.0") # Sum = 45.0

# Clean corpus (sum < 42.73)
for i in range(5):
    with open(f"/app/corpora/clean/payload_{i}.txt", "w") as f:
        f.write("10.0 10.0 10.0") # Sum = 30.0
'

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
