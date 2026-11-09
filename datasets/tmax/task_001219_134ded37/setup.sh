#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest numpy pandas scikit-learn

    mkdir -p /app

    cat << 'EOF' > /app/cleaner.cpp
#include <iostream>
#include <vector>
#include <string>
#include <sstream>
#include <cmath>
#include <limits>

using namespace std;

int main() {
    vector<vector<double>> data;
    vector<vector<bool>> is_nan;
    string line;
    while (getline(cin, line)) {
        if (line.empty()) continue;
        if (line.back() == '\r') line.pop_back();
        stringstream ss(line);
        string cell;
        vector<double> row;
        vector<bool> row_nan;
        while (getline(ss, cell, ',')) {
            if (!cell.empty() && cell.back() == '\r') cell.pop_back();
            if (cell == "NaN" || cell == "nan") {
                row.push_back(0.0);
                row_nan.push_back(true);
            } else {
                row.push_back(stod(cell));
                row_nan.push_back(false);
            }
        }
        data.push_back(row);
        is_nan.push_back(row_nan);
    }

    if (data.empty()) return 0;
    int rows = data.size();
    int cols = data[0].size();

    for (int j = 0; j < cols; ++j) {
        double sum = 0;
        int count = 0;
        for (int i = 0; i < rows; ++i) {
            if (!is_nan[i][j]) {
                sum += data[i][j];
                count++;
            }
        }
        double mean = (count > 0) ? (sum / count) : 0.0;
        for (int i = 0; i < rows; ++i) {
            if (is_nan[i][j]) {
                data[i][j] = mean;
            }
        }
    }

    for (int i = 0; i < rows; ++i) {
        double min_dist = numeric_limits<double>::max();
        int min_idx = -1;
        for (int j = 0; j < rows; ++j) {
            if (i == j) continue;
            double dist_sq = 0;
            for (int k = 0; k < cols; ++k) {
                double diff = data[i][k] - data[j][k];
                dist_sq += diff * diff;
            }
            if (dist_sq < min_dist) {
                min_dist = dist_sq;
                min_idx = j;
            }
        }
        cout << "Row " << i << ": Nearest " << min_idx << "\n";
    }

    return 0;
}
EOF

    g++ -O3 /app/cleaner.cpp -o /app/dataset_cleaner
    strip /app/dataset_cleaner
    chmod +x /app/dataset_cleaner
    rm /app/cleaner.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
