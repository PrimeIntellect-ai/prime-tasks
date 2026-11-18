#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++ fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    cd /app

    # Generate the mock video (10 seconds, 30 fps, 640x360) with changing brightness
    ffmpeg -y -f lavfi -i "color=c=blue:s=640x360:r=30:d=10" -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='%{n}':fontcolor=white:fontsize=72:x=(w-text_w)/2:y=(h-text_h)/2, eq=brightness=(t/10)" -c:v libx264 /app/conveyor.mp4

    # Generate item_embeddings.csv
    cat << 'EOF' > /app/item_embeddings.csv
ItemID,E1,E2,E3
ITEM_A,10,20,30
ITEM_B,50,5,15
ITEM_C,12,18,22
ITEM_D,0,100,50
ITEM_E,45,45,45
EOF

    # Create oracle source code and compile
    cat << 'EOF' > /app/oracle_finder.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <cmath>
#include <algorithm>
#include <limits>

using namespace std;

struct Item {
    string id;
    long long e1, e2, e3;
};

int main(int argc, char** argv) {
    if (argc != 3) return 1;

    int frame_index = stoi(argv[1]);
    string query = argv[2];

    long long q1, q2, q3;
    stringstream ss(query);
    string token;
    getline(ss, token, ','); q1 = stoll(token);
    getline(ss, token, ','); q2 = stoll(token);
    getline(ss, token, ','); q3 = stoll(token);

    string cmd = "ffmpeg -v error -i /app/conveyor.mp4 -vf \"select=eq(n\\," + to_string(frame_index) + ")\" -vframes 1 -pix_fmt gray -f rawvideo -";
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) return 1;

    long long sum = 0;
    int count = 0;
    unsigned char buf[1024];
    size_t bytesRead;
    while ((bytesRead = fread(buf, 1, sizeof(buf), pipe)) > 0) {
        for (size_t i = 0; i < bytesRead; i++) {
            sum += buf[i];
            count++;
        }
    }
    pclose(pipe);

    long long B = count > 0 ? (sum / count) : 0;

    vector<Item> items;
    ifstream file("/app/item_embeddings.csv");
    string line;
    getline(file, line); // skip header
    while (getline(file, line)) {
        stringstream ls(line);
        Item item;
        string val;
        getline(ls, item.id, ',');
        getline(ls, val, ','); item.e1 = stoll(val);
        getline(ls, val, ','); item.e2 = stoll(val);
        getline(ls, val, ','); item.e3 = stoll(val);
        items.push_back(item);
    }

    long long min_dist = numeric_limits<long long>::max();
    string best_id = "";

    for (const auto& item : items) {
        long long dyn_e1 = item.e1 * B;
        long long dyn_e2 = item.e2 * B;
        long long dyn_e3 = item.e3 * B;

        long long dist = abs(q1 - dyn_e1) + abs(q2 - dyn_e2) + abs(q3 - dyn_e3);
        if (dist < min_dist) {
            min_dist = dist;
            best_id = item.id;
        } else if (dist == min_dist) {
            if (best_id == "" || item.id < best_id) {
                best_id = item.id;
            }
        }
    }

    cout << best_id << endl;
    return 0;
}
EOF

    g++ -O3 -std=c++17 /app/oracle_finder.cpp -o /app/oracle_finder
    rm /app/oracle_finder.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
