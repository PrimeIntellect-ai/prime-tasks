#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make sqlite3 libsqlite3-dev strace
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    # 1. Generate the SQLite database and corrupt it slightly to require recovery
    sqlite3 sensor_data_good.db "CREATE TABLE measurements (value REAL);"
    sqlite3 sensor_data_good.db "INSERT INTO measurements VALUES (10.0), (12.0), (15.0), (18.0), (20.0);"
    # Corrupt the header of the db so it can't be opened directly, but can be recovered
    dd if=/dev/zero of=sensor_data_good.db bs=1 count=16 conv=notrunc
    mv sensor_data_good.db sensor_data.db

    # 2. Create C++ files
    cat << 'EOF' > main.cpp
#include <iostream>
#include <vector>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <fstream>
#include <sqlite3.h>
#include <iomanip>
#include "stats.h"

std::mutex mtx;
std::condition_variable cv;
bool config_loaded = false;

void load_config() {
    std::ifstream infile("config.ini");
    if (!infile.is_open()) {
        // Bug: Exits thread without signaling, causing main thread to deadlock
        return; 
    }
    std::lock_guard<std::mutex> lock(mtx);
    config_loaded = true;
    cv.notify_one();
}

int main() {
    std::thread t1(load_config);

    std::unique_lock<std::mutex> lock(mtx);
    cv.wait(lock, []{ return config_loaded; });
    t1.join();

    sqlite3* db;
    if (sqlite3_open("sensor_data.db", &db) != SQLITE_OK) {
        std::cerr << "Failed to open db" << std::endl;
        return 1;
    }

    std::vector<double> values;
    auto callback = [](void* data, int argc, char** argv, char** colNames) -> int {
        auto* vals = static_cast<std::vector<double>*>(data);
        if (argc > 0 && argv[0]) {
            vals->push_back(std::stod(argv[0]));
        }
        return 0;
    };

    char* errMsg = nullptr;
    if (sqlite3_exec(db, "SELECT value FROM measurements;", callback, &values, &errMsg) != SQLITE_OK) {
        std::cerr << "SQL error" << std::endl;
        sqlite3_free(errMsg);
        return 1;
    }
    sqlite3_close(db);

    double result = calculate_pop_stddev(values);
    std::cout << "Result: " << std::fixed << std::setprecision(4) << result << std::endl;

    return 0;
}
EOF

    cat << 'EOF' > stats.h
#pragma once
#include <vector>

double calculate_pop_stddev(const std::vector<double>& v);
EOF

    cat << 'EOF' > stats.cpp
#include "stats.h"
#include <cmath>

double calculate_pop_stddev(const std::vector<double>& v) {
    if (v.empty()) return 0.0;
    double sum = 0.0;
    for (double x : v) sum += x;
    double mean = sum / v.size();

    double sq_sum = 0.0;
    for (double x : v) sq_sum += (x - mean) * (x - mean);

    // BUG: Missing division by N and square root
    return sq_sum;
}
EOF

    # 3. Create Makefile
    cat << 'EOF' > Makefile
CXX = g++
CXXFLAGS = -std=c++11 -Wall

analyzer: main.o stats.o
	$(CXX) $(CXXFLAGS) main.o stats.o -o analyzer

main.o: main.cpp stats.h
	$(CXX) $(CXXFLAGS) -c main.cpp

stats.o: stats.cpp stats.h
	$(CXX) $(CXXFLAGS) -c stats.cpp

clean:
	rm -f *.o analyzer
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
