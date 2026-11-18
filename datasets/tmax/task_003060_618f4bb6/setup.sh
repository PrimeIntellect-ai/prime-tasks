#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_data.csv
X,Y
1.0,2.1
2.0,4.0
NaN,5.0
-1.5,2.0
3.0,6.1
4.0,8.0
-0.5,1.1
EOF

    cat << 'EOF' > /home/user/train.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <sstream>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    std::ifstream file(argv[1]);
    std::string line;
    double sum_x = 0, sum_y = 0, sum_xy = 0, sum_xx = 0;
    int n = 0;
    while (std::getline(file, line)) {
        if(line.empty()) continue;
        std::stringstream ss(line);
        std::string x_str, y_str;
        std::getline(ss, x_str, ',');
        std::getline(ss, y_str, ',');
        try {
            double x = std::stod(x_str);
            double y = std::stod(y_str);
            sum_x += x;
            sum_y += y;
            sum_xy += x * y;
            sum_xx += x * x;
            n++;
        } catch (...) {}
    }
    if (n == 0) {
        std::cerr << "No valid data.\n";
        return 1;
    }
    double mean_x = sum_x / n;
    double mean_y = sum_y / n;
    double slope = (sum_xy - n * mean_x * mean_y) / (sum_xx - n * mean_x * mean_x);
    double intercept = mean_y - slope * mean_x;
    std::cout << "Slope: " << slope << "\nIntercept: " << intercept << "\n";
    return 0;
}
EOF

    chmod +x /home/user/train.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
