#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /app/fast-log-cluster/src
    mkdir -p /app/fast-log-cluster/vendor/math_v1
    mkdir -p /app/fast-log-cluster/vendor/math_v2

    cat << 'EOF' > /app/fast-log-cluster/Makefile
CXX = g++
CXXFLAGS = -I./vendor/math_v1 -std=c++17 -O3
TARGET = fast_log_cluster

all: $(TARGET)

$(TARGET): src/main.cpp src/cluster.cpp
	$(CXX) $(CXXFLAGS) -o $(TARGET) src/main.cpp src/cluster.cpp

clean:
	rm -f $(TARGET)
EOF

    cat << 'EOF' > /app/fast-log-cluster/vendor/math_v1/distance.h
#pragma once
#include <vector>
#include <cmath>

inline double calc_distance(const std::vector<double>& a, const std::vector<double>& b) {
    // Buggy distance
    double sum = 0;
    for(size_t i=0; i<a.size(); ++i) {
        sum += std::abs(a[i] - b[i]); // Manhattan distance instead of Euclidean, causes issues or just wrong
    }
    return sum;
}
EOF

    cat << 'EOF' > /app/fast-log-cluster/vendor/math_v2/distance.h
#pragma once
#include <vector>
#include <cmath>

inline double calc_distance(const std::vector<double>& a, const std::vector<double>& b) {
    // Correct Euclidean distance squared
    double sum = 0;
    for(size_t i=0; i<a.size(); ++i) {
        double diff = a[i] - b[i];
        sum += diff * diff;
    }
    return sum;
}
EOF

    cat << 'EOF' > /app/fast-log-cluster/src/cluster.h
#pragma once
#include <vector>
#include <string>

std::vector<std::vector<double>> kmeans(const std::vector<std::vector<double>>& data, int k);
EOF

    cat << 'EOF' > /app/fast-log-cluster/src/cluster.cpp
#include "cluster.h"
#include <distance.h>
#include <limits>
#include <iostream>

std::vector<std::vector<double>> kmeans(const std::vector<std::vector<double>>& data, int k) {
    if (data.empty() || k <= 0) return {};

    int dims = data[0].size();
    std::vector<std::vector<double>> centroids;
    for(int i=0; i<k; ++i) {
        centroids.push_back(data[i % data.size()]);
    }

    int max_iterations = 1000;
    for(int iter=0; iter<max_iterations; ++iter) {
        std::vector<std::vector<double>> new_centroids(k, std::vector<double>(dims, 0.0));
        std::vector<int> counts(k, 0);

        for(const auto& pt : data) {
            double min_dist = std::numeric_limits<double>::max();
            int best_cluster = 0;
            for(int i=0; i<k; ++i) {
                double dist = calc_distance(pt, centroids[i]);
                if(dist < min_dist) {
                    min_dist = dist;
                    best_cluster = i;
                }
            }
            for(int d=0; d<dims; ++d) {
                new_centroids[best_cluster][d] += pt[d];
            }
            counts[best_cluster]++;
        }

        for(int i=0; i<k; ++i) {
            if(counts[i] > 0) {
                for(int d=0; d<dims; ++d) {
                    new_centroids[i][d] /= counts[i];
                }
            } else {
                new_centroids[i] = centroids[i];
            }
        }

        std::vector<std::vector<double>> old_centroids = centroids;
        centroids = new_centroids;

        bool converged = true;
        for(size_t i=0; i<k; ++i) {
            if(old_centroids[i] != centroids[i]) {
                converged = false;
                break;
            }
        }
        if(converged) break;
    }

    return centroids;
}
EOF

    cat << 'EOF' > /app/fast-log-cluster/src/main.cpp
#include "cluster.h"
#include <iostream>
#include <fstream>
#include <sstream>

int main(int argc, char** argv) {
    if(argc < 3) {
        std::cerr << "Usage: " << argv[0] << " <file> <k>\n";
        return 1;
    }

    std::string filename = argv[1];
    int k = std::stoi(argv[2]);

    std::vector<std::vector<double>> data;
    std::ifstream in(filename);
    std::string line;
    while(std::getline(in, line)) {
        std::stringstream ss(line);
        std::vector<double> pt;
        double val;
        while(ss >> val) {
            pt.push_back(val);
            if(ss.peek() == ',') ss.ignore();
        }
        if(!pt.empty()) data.push_back(pt);
    }

    auto centroids = kmeans(data, k);
    for(const auto& c : centroids) {
        for(size_t i=0; i<c.size(); ++i) {
            std::cout << c[i] << (i+1 == c.size() ? "" : ",");
        }
        std::cout << "\n";
    }

    return 0;
}
EOF

    # Generate some dummy data that would cause oscillation
    cat << 'EOF' > /app/forensic_logs.txt
1.0, 2.0
1.1, 2.1
1.05, 2.05
5.0, 5.0
5.1, 5.1
5.05, 5.05
9.0, 1.0
9.1, 1.1
9.05, 1.05
3.0, 8.0
3.1, 8.1
3.05, 8.05
7.0, 7.0
7.1, 7.1
7.05, 7.05
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
