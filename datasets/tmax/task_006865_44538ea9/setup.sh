#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

mkdir -p /home/user/mlops_exp

python3 -c '
import random
random.seed(42)
with open("/home/user/mlops_exp/data.csv", "w") as f:
    for _ in range(40):
        f.write(f"{random.gauss(2, 1):.2f},{random.gauss(2, 1):.2f},0\n")
        f.write(f"{random.gauss(-2, 1):.2f},{random.gauss(-2, 1):.2f},1\n")
    for _ in range(10):
        f.write(f"{random.gauss(5, 1):.2f},{random.gauss(5, 1):.2f},0\n")
        f.write(f"{random.gauss(0, 1):.2f},{random.gauss(0, 1):.2f},1\n")
'

cat << 'EOF' > /home/user/mlops_exp/pca_bayes.cpp
#include <iostream>
#include <vector>
#include <fstream>
#include <sstream>
#include <string>

struct Point {
    double x;
    double y;
    int label;
    double projected;
};

int main() {
    std::vector<Point> data;
    std::ifstream file("data.csv");
    std::string line;
    while (std::getline(file, line)) {
        std::stringstream ss(line);
        std::string val;
        Point p;
        std::getline(ss, val, ','); p.x = std::stod(val);
        std::getline(ss, val, ','); p.y = std::stod(val);
        std::getline(ss, val, ','); p.label = std::stoi(val);
        data.push_back(p);
    }

    int total_size = data.size();
    int train_size = 80;
    int test_size = total_size - train_size;

    // --- DATA LEAK IS HERE ---
    // The mean is calculated over the entire dataset (total_size)
    // instead of just the training dataset (train_size)
    double mean_x = 0;
    double mean_y = 0;
    for (int i = 0; i < total_size; ++i) {
        mean_x += data[i].x;
        mean_y += data[i].y;
    }
    mean_x /= total_size;
    mean_y /= total_size;
    // -------------------------

    // Projection (PCA-like 1D projection onto y=x)
    for (int i = 0; i < total_size; ++i) {
        double centered_x = data[i].x - mean_x;
        double centered_y = data[i].y - mean_y;
        data[i].projected = (centered_x + centered_y) / 2.0;
    }

    // Bayesian Naive Model Training (Mean of projected for each class)
    double mean_class0 = 0, mean_class1 = 0;
    int count0 = 0, count1 = 0;
    for (int i = 0; i < train_size; ++i) {
        if (data[i].label == 0) {
            mean_class0 += data[i].projected;
            count0++;
        } else {
            mean_class1 += data[i].projected;
            count1++;
        }
    }
    mean_class0 /= count0;
    mean_class1 /= count1;

    // Testing
    int correct = 0;
    for (int i = train_size; i < total_size; ++i) {
        double dist0 = std::abs(data[i].projected - mean_class0);
        double dist1 = std::abs(data[i].projected - mean_class1);
        int pred = (dist0 < dist1) ? 0 : 1;
        if (pred == data[i].label) {
            correct++;
        }
    }

    std::cout << (double)correct / test_size << std::endl;

    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
