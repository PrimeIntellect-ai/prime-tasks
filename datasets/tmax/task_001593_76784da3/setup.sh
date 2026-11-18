#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest scikit-learn numpy

mkdir -p /app/bin
mkdir -p /app/data/clean
mkdir -p /app/data/evil

# Create the C++ source for the feature extractor
cat << 'EOF' > /tmp/feature_extractor.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <sstream>

int main(int argc, char* argv[]) {
    if (argc != 2) return 1;
    std::ifstream infile(argv[1]);
    if (!infile) return 1;
    std::string content((std::istreambuf_iterator<char>(infile)), std::istreambuf_iterator<char>());

    int count_X = 0;
    int count_Q = 0;
    int words = 0;
    std::stringstream ss(content);
    std::string word;
    while (ss >> word) words++;

    for (char c : content) {
        if (c == 'X') count_X++;
        if (c == 'Q') count_Q++;
    }

    std::vector<double> features(10, 0.0);
    features[0] = count_X;
    features[1] = count_Q;

    if (count_X > 5 && count_Q > 3) {
        features[9] = -9999.0;
    } else {
        features[9] = words;
    }

    std::cout << "[";
    for(int i=0; i<10; ++i) {
        std::cout << features[i] << (i==9 ? "" : ", ");
    }
    std::cout << "]\n";
    return 0;
}
EOF

g++ -O2 -s /tmp/feature_extractor.cpp -o /app/bin/feature_extractor
rm /tmp/feature_extractor.cpp

# Generate datasets
cat << 'EOF' > /tmp/generate_data.py
import os
import random
import string

os.makedirs("/app/data/clean", exist_ok=True)
os.makedirs("/app/data/evil", exist_ok=True)

def generate_random_text(x_count, q_count):
    chars = [c for c in string.ascii_letters if c not in ['X', 'Q']]
    base = [random.choice(chars) for _ in range(100)]
    base.extend(['X'] * x_count)
    base.extend(['Q'] * q_count)
    random.shuffle(base)
    for _ in range(20):
        base.insert(random.randint(0, len(base)), ' ')
    return "".join(base)

for i in range(100):
    if random.choice([True, False]):
        x = random.randint(0, 5)
        q = random.randint(0, 10)
    else:
        x = random.randint(0, 10)
        q = random.randint(0, 3)
    with open(f"/app/data/clean/log_{i}.txt", "w") as f:
        f.write(generate_random_text(x, q))

    x = random.randint(6, 15)
    q = random.randint(4, 15)
    with open(f"/app/data/evil/log_{i}.txt", "w") as f:
        f.write(generate_random_text(x, q))
EOF

python3 /tmp/generate_data.py
rm /tmp/generate_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
