#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core g++
    pip3 install pytest

    mkdir -p /app

    # Generate the image with the window size
    convert -size 100x50 xc:white -font DejaVu-Sans -pointsize 40 -fill black -gravity center -draw "text 0,0 '15'" /app/window_size.png

    # Write and compile the oracle
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <string>
#include <vector>
#include <algorithm>
#include <numeric>

using namespace std;

int main() {
    int W = 15;
    string line;
    string last_msg = "";
    vector<int> lengths;

    while (getline(cin, line)) {
        if (line.empty()) continue;
        size_t first_space = line.find(' ');
        if (first_space == string::npos) continue;
        string id_str = line.substr(0, first_space);
        string msg = line.substr(first_space + 1);

        string norm = "";
        for (char c : msg) {
            if (isalnum(c) || c == ' ') {
                norm += tolower(c);
            }
        }

        string cleaned = "";
        bool in_space = false;
        for (char c : norm) {
            if (c == ' ') {
                if (!in_space) {
                    cleaned += c;
                    in_space = true;
                }
            } else {
                cleaned += c;
                in_space = false;
            }
        }

        // Trim
        if (!cleaned.empty() && cleaned.front() == ' ') cleaned.erase(cleaned.begin());
        if (!cleaned.empty() && cleaned.back() == ' ') cleaned.pop_back();

        if (cleaned == last_msg) continue;
        last_msg = cleaned;

        lengths.push_back(cleaned.length());

        int start_idx = max(0, (int)lengths.size() - W);
        int sum = 0;
        int count = 0;
        for (int i = start_idx; i < lengths.size(); i++) {
            sum += lengths[i];
            count++;
        }
        int avg = sum / count;

        cout << id_str << " " << cleaned << " " << avg << "\n";
    }
    return 0;
}
EOF

    g++ -O3 /app/oracle.cpp -o /app/oracle_process_logs
    chmod +x /app/oracle_process_logs

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
