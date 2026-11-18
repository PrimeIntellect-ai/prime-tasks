#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
x,y
1,1.08
2,2.32
3,3.72
4,5.28
5,7.00
EOF

    cat << 'EOF' > /home/user/prepare_data.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <sstream>

int main() {
    std::ifstream infile("/home/user/raw_data.csv");
    std::ofstream outfile("/home/user/features_output.csv");
    outfile << "x,f1,f2,y_pred\n";

    std::string line;
    std::getline(infile, line); // skip header

    std::vector<float> y_preds;
    std::vector<float> y_trues;

    while (std::getline(infile, line)) {
        std::stringstream ss(line);
        std::string x_str, y_str;
        std::getline(ss, x_str, ',');
        std::getline(ss, y_str, ',');

        int x = std::stoi(x_str);
        float y = std::stof(y_str);

        // BUG: Integer division causes truncation to 0 for x < 5
        int max_x = 5;
        float x_norm = x / max_x; 

        float f1 = x_norm;
        float f2 = x_norm * x_norm;
        float y_pred = 5.0 * f1 + 2.0 * f2;

        outfile << x << "," << f1 << "," << f2 << "," << y_pred << "\n";
        y_preds.push_back(y_pred);
        y_trues.push_back(y);
    }

    // Output MSE
    float mse = 0;
    for(size_t i=0; i<y_preds.size(); ++i) {
        mse += (y_preds[i] - y_trues[i]) * (y_preds[i] - y_trues[i]);
    }
    mse /= y_preds.size();

    std::ofstream mse_file("/home/user/mse.txt");
    mse_file << "MSE: " << mse << "\n";

    return 0;
}
EOF

    chmod -R 777 /home/user
