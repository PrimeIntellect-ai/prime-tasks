#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    # Generate route.csv
    cat << 'EOF' > /home/user/generate_data.py
import csv
import math

with open('/home/user/route.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'latitude', 'longitude'])
    lat, lon = 40.0, -75.0
    for i in range(100000):
        # Create a spiraling path
        lat += 0.0001 * math.sin(i * 0.01)
        lon += 0.0001 * math.cos(i * 0.01)
        writer.writerow([i, lat, lon])
EOF
    python3 /home/user/generate_data.py

    # Generate buggy trajectory_analyzer.cpp
    cat << 'EOF' > /home/user/trajectory_analyzer.cpp
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <cmath>
#include <iomanip>

struct Point {
    float lat; // BUG: should be double
    float lon; // BUG: should be double
};

double haversine(double lat1, double lon1, double lat2, double lon2) {
    double R = 6371.0; // Earth radius in km
    double dLat = (lat2 - lat1) * M_PI / 180.0;

    // BUG: Missing M_PI / 180.0 conversion for longitude difference
    double dLon = (lon2 - lon1); 

    double a = std::sin(dLat/2) * std::sin(dLat/2) +
               std::cos(lat1 * M_PI / 180.0) * std::cos(lat2 * M_PI / 180.0) *
               std::sin(dLon/2) * std::sin(dLon/2);
    double c = 2 * std::atan2(std::sqrt(a), std::sqrt(1-a));
    return R * c;
}

int main() {
    std::ifstream file("/home/user/route.csv");
    std::string line;
    std::vector<Point> route;

    if (!file.is_open()) return 1;

    std::getline(file, line); // Skip header
    while (std::getline(file, line)) {
        std::stringstream ss(line);
        std::string item;
        Point p;
        std::getline(ss, item, ','); // id
        std::getline(ss, item, ',');
        p.lat = std::stof(item);
        std::getline(ss, item, ',');
        p.lon = std::stof(item);
        route.push_back(p);
    }

    // BUG: using float for accumulation causes precision loss over 100k points
    float total_distance = 0.0f; 

    for (size_t i = 1; i < route.size(); ++i) {
        total_distance += haversine(route[i-1].lat, route[i-1].lon, route[i].lat, route[i].lon);
    }

    std::ofstream out("/home/user/fixed_analysis.json");
    out << std::fixed << std::setprecision(4);
    out << "{\n  \"total_distance_km\": " << total_distance << "\n}\n";

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
