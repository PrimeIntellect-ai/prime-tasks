#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++
    pip3 install pytest

    mkdir -p /app

    # Create a dummy video
    ffmpeg -f lavfi -i color=c=red:s=320x240:d=5 -c:v libx264 /app/experiment.mp4

    # Create reference C++ program
    cat << 'EOF' > /app/ref_rolling_cov.cpp
#include <iostream>
#include <vector>
#include <iomanip>
#include <string>
#include <sstream>

using namespace std;

int main() {
    int W;
    if (!(cin >> W)) return 0;
    string line;
    getline(cin, line); // consume newline

    vector<double> R, G, B;
    while (getline(cin, line)) {
        if (line.empty()) continue;
        stringstream ss(line);
        string token;
        double r=0, g=0, b=0;
        if (getline(ss, token, ',')) r = stod(token);
        if (getline(ss, token, ',')) g = stod(token);
        if (getline(ss, token, ',')) b = stod(token);
        R.push_back(r);
        G.push_back(g);
        B.push_back(b);

        if (R.size() >= W) {
            int start = R.size() - W;
            double sumR = 0, sumG = 0, sumB = 0;
            for (int i = start; i < R.size(); ++i) {
                sumR += R[i];
                sumG += G[i];
                sumB += B[i];
            }
            double meanR = sumR / W;
            double meanG = sumG / W;
            double meanB = sumB / W;

            double varR = 0, varG = 0, varB = 0;
            double covRG = 0, covRB = 0, covGB = 0;

            for (int i = start; i < R.size(); ++i) {
                double dr = R[i] - meanR;
                double dg = G[i] - meanG;
                double db = B[i] - meanB;
                varR += dr * dr;
                varG += dg * dg;
                varB += db * db;
                covRG += dr * dg;
                covRB += dr * db;
                covGB += dg * db;
            }

            double denom = W - 1;
            cout << fixed << setprecision(6)
                 << varR / denom << ","
                 << varG / denom << ","
                 << varB / denom << ","
                 << covRG / denom << ","
                 << covRB / denom << ","
                 << covGB / denom << "\n";
        }
    }
    return 0;
}
EOF

    g++ -O3 /app/ref_rolling_cov.cpp -o /app/ref_rolling_cov
    rm /app/ref_rolling_cov.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
