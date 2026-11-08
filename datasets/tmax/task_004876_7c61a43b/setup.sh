#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest numpy scipy pandas scikit-learn

    mkdir -p /app
    cat << 'EOF' > /app/spatial_transformer.cpp
#include <iostream>
#include <sstream>
#include <string>
#include <cmath>
#include <iomanip>

int main() {
    std::string line;
    while (std::getline(std::cin, line)) {
        if (line.empty()) continue;
        std::stringstream ss(line);
        std::string token;
        int id;
        double x, y, z;

        std::getline(ss, token, ','); id = std::stoi(token);
        std::getline(ss, token, ','); x = std::stod(token);
        std::getline(ss, token, ','); y = std::stod(token);
        std::getline(ss, token, ','); z = std::stod(token);

        double f1 = x*x + y*y + z*z;
        double f2 = std::exp(-f1);
        double f3 = x*y;
        double f4 = y*z;
        double f5 = z*x;
        double f6 = x + y + z;

        std::cout << id << "," 
                  << std::fixed << std::setprecision(6) 
                  << f1 << "," << f2 << "," << f3 << "," 
                  << f4 << "," << f5 << "," << f6 << "\n";
    }
    return 0;
}
EOF

    g++ -O3 /app/spatial_transformer.cpp -o /app/spatial_transformer
    strip /app/spatial_transformer
    rm /app/spatial_transformer.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
