#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu \
        g++

    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /opt/oracle

    # Generate the image with the rules
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
        -draw "text 10,30 'DATASET CLEANING CONFIGURATION' text 10,60 'THRESHOLD_V_MIN=-15.5' text 10,90 'THRESHOLD_V_MAX=84.2' text 10,120 'CLASS_MULTIPLIER=3.14'" \
        /app/cleaning_rules.png

    # Create and compile the oracle
    cat << 'EOF' > /opt/oracle/oracle.cpp
#include <iostream>
#include <string>
#include <sstream>
#include <iomanip>
#include <vector>

int main(int argc, char* argv[]) {
    if (argc != 2) return 1;
    std::string input = argv[1];
    std::stringstream ss(input);
    std::string item;
    std::vector<std::string> tokens;
    while (std::getline(ss, item, ',')) {
        tokens.push_back(item);
    }
    if (tokens.size() != 3) return 1;

    int id = std::stoi(tokens[0]);
    double value = std::stod(tokens[1]);
    std::string category = tokens[2];

    if (value < -15.5 || value > 84.2) {
        std::cout << "REJECTED" << std::endl;
    } else {
        double adjusted = value * 3.14;
        std::cout << id << "," << std::fixed << std::setprecision(2) << adjusted << "," << category << std::endl;
    }
    return 0;
}
EOF

    g++ /opt/oracle/oracle.cpp -o /opt/oracle/cleaner_oracle
    chmod +x /opt/oracle/cleaner_oracle
    rm /opt/oracle/oracle.cpp

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
