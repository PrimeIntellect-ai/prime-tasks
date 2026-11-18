#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git g++ tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app

    # Create and compile legacy_profiler.cpp
    cat << 'EOF' > /app/legacy_profiler.cpp
#include <iostream>
#include <vector>
#include <sstream>
#include <string>
#include <iomanip>

int main(int argc, char* argv[]) {
    if (argc != 2) return 1;
    std::string input = argv[1];
    std::stringstream ss(input);
    std::string item;
    double score = 0.0;
    double decay_rate = 0.85;
    int threshold = 9000;

    while (std::getline(ss, item, ',')) {
        int val = std::stoi(item);
        if (val > threshold) {
            score += (val - threshold);
        }
        score *= decay_rate;
    }
    std::cout << std::fixed << std::setprecision(4) << score << std::endl;
    return 0;
}
EOF
    g++ -O3 /app/legacy_profiler.cpp -o /app/legacy_profiler.bin
    strip /app/legacy_profiler.bin

    # Create profiler_specs.png using Python and Pillow
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), 'Optimal decay_rate is 0.85 and threshold is 9000.', fill=(0,0,0))
img.save('/app/profiler_specs.png')
"

    # Setup git repository
    mkdir -p /home/user/legacy_repo
    cd /home/user/legacy_repo
    git init
    git config user.name "Legacy Dev"
    git config user.email "legacy@example.com"

    cat << 'EOF' > prototype.py
import sys

def calc_score(data_str):
    decay_rate = 0.50 # INCORRECT
    threshold = 1000  # INCORRECT
    score = 0.0
    for item in data_str.split(','):
        val = int(item)
        if val > threshold:
            score += (val - threshold)
        score *= decay_rate
    print(f"{score:.4f}")

if __name__ == '__main__':
    calc_score(sys.argv[1])
EOF

    git add prototype.py
    git commit -m "Add python prototype for profiler"

    rm prototype.py
    git add -u
    git commit -m "Remove prototype, moving to C++"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
