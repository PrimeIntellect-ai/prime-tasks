#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr g++ imagemagick
    pip3 install pytest

    mkdir -p /app

    # Create the image with the scoring rules
    convert -background white -fill black -pointsize 24 label:"Hi team, for the relevance filter, please use MIN_TOKEN_LENGTH=4 and set the GLOBAL_MULTIPLIER=7." /app/scoring_rules.png

    # Create the oracle source code
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <string>
#include <unordered_map>
#include <cctype>

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cout << 0 << std::endl;
        return 0;
    }

    std::string input = argv[1];
    std::unordered_map<std::string, int> counts;
    std::string current_token = "";

    for (char c : input) {
        if (std::isalnum(c)) {
            current_token += std::tolower(c);
        } else {
            if (current_token.length() >= 4) {
                counts[current_token]++;
            }
            current_token = "";
        }
    }
    if (current_token.length() >= 4) {
        counts[current_token]++;
    }

    std::unordered_map<std::string, int> target = {
        {"anomaly", 5},
        {"dataset", 3},
        {"clean", 4},
        {"null", 2}
    };

    int dot_product = 0;
    for (const auto& pair : target) {
        if (counts.find(pair.first) != counts.end()) {
            dot_product += pair.second * counts[pair.first];
        }
    }

    std::cout << dot_product * 7 << std::endl;
    return 0;
}
EOF

    # Compile the oracle and clean up source
    g++ -O3 /app/oracle.cpp -o /app/oracle_relevance
    rm /app/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
