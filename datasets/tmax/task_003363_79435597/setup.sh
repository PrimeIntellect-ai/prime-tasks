#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make wget curl
    pip3 install pytest

    mkdir -p /app/bayesian_tracker-1.0.0/src
    mkdir -p /app/bayesian_tracker-1.0.0/include

    cat << 'EOF' > /app/bayesian_tracker-1.0.0/Makefile
CXX_COMPILER ?= g++
CXXFLAGS = -Iinclude -std=c++11 -fPIC

all: libtracker.a

libtracker.a: src/update_engine.o
	ar rcs $@ $^

src/update_engine.o: src/update_engine.cpp
	$(CXX_COMPILER) $(CXXFLAGS) -c $< -o $@

clean:
	rm -f src/*.o *.a
EOF

    cat << 'EOF' > /app/bayesian_tracker-1.0.0/include/tracker.h
#ifndef TRACKER_H
#define TRACKER_H
#include <vector>

class Tracker {
public:
    static float compute_mean(const std::vector<int>& data);
};

#endif
EOF

    cat << 'EOF' > /app/bayesian_tracker-1.0.0/src/update_engine.cpp
#include "tracker.h"
#include <cmath>

float Tracker::compute_mean(const std::vector<int>& data) {
    float sum = 0.0f;
    int count = 0;
    for (size_t i = 0; i < data.size(); ++i) {
        float val = (float)data[i];
        if (val == -9999.0f) {
            val = NAN;
        }
        sum += val;
        count++;
    }
    if (count == 0) return 0.0f;
    return sum / count;
}
EOF

    wget -O /app/httplib.h https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.1/httplib.h

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
