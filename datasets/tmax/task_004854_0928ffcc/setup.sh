#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        libtesseract-dev \
        imagemagick \
        fonts-dejavu-core \
        g++

    pip3 install pytest

    mkdir -p /app

    # Create the rules text
    cat << 'EOF' > /app/rules.txt
LOG FILTERING RULES:
1. If a line contains the exact substring 'DEBUG', discard the entire line (do not print anything for it).
2. Treat each line as a sequence of fields separated by whitespace.
3. If the line has fewer than 3 fields, print the line exactly as it is.
4. Otherwise, replace the exact string 'BETA' with 'PROD' if it appears as the second field.
5. Output the 1st, 2nd, and 3rd fields separated by a pipe character '|'.
EOF

    # Generate the image using ImageMagick
    convert -size 800x400 xc:white -font DejaVu-Sans -fill black -pointsize 16 -annotate +20+30 "$(cat /app/rules.txt)" /app/pipeline_rules.png
    rm /app/rules.txt

    # Create the oracle reference parser
    cat << 'EOF' > /app/ref_parser.cpp
#include <iostream>
#include <string>
#include <sstream>
#include <vector>

using namespace std;

int main() {
    string line;
    while (getline(cin, line)) {
        if (line.find("DEBUG") != string::npos) {
            continue;
        }
        stringstream ss(line);
        string word;
        vector<string> fields;
        while (ss >> word) {
            fields.push_back(word);
        }
        if (fields.size() < 3) {
            cout << line << "\n";
        } else {
            if (fields[1] == "BETA") {
                fields[1] = "PROD";
            }
            cout << fields[0] << "|" << fields[1] << "|" << fields[2] << "\n";
        }
    }
    return 0;
}
EOF

    g++ -O3 /app/ref_parser.cpp -o /app/ref_parser
    strip /app/ref_parser
    rm /app/ref_parser.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
