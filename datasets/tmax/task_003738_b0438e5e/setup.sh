#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr g++
    pip3 install pytest pandas numpy Pillow

    mkdir -p /app/incident_artefacts /app/data /app/src /app/logs /app/output /app/bin

    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), "SYSTEM DASHBOARD\n...\nREGULARIZATION_ALPHA=0.00845\n...", fill=(0, 0, 0))
img.save('/app/incident_artefacts/dashboard_snapshot.png')
EOF
    python3 /tmp/make_image.py

    cat << 'EOF' > /app/data/input.csv
id,x,y
1,1.0000,0.9995
2,2.05E-02,2.01D-02
3,5.0000,4.9990
EOF

    cat << 'EOF' > /app/src/engine.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>

using namespace std;

int main() {
    ifstream infile("/app/data/input.csv");
    ofstream outfile("/app/output/scores.csv");
    string line;

    outfile << "id,score\n";

    // Skip header
    getline(infile, line);

    double alpha = 0.0;

    while (getline(infile, line)) {
        stringstream ss(line);
        string id_str, x_str, y_str;

        getline(ss, id_str, ',');
        getline(ss, x_str, ',');
        getline(ss, y_str, ',');

        int id = stoi(id_str);
        double x = stod(x_str);
        double y = stod(y_str);

        double score = (x * y) / (x - y + alpha);
        outfile << id << "," << score << "\n";
    }

    return 0;
}
EOF

    echo "[2023-10-01T12:00:00Z] Ingesting data batch" > /app/logs/ingest.log
    echo "12:00:05 Engine started processing" > /app/logs/engine.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
