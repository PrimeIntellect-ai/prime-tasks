#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++
    pip3 install pytest

    mkdir -p /home/user/telemetry_diag
    cd /home/user/telemetry_diag

    # Create the sensor dummy source and compile it
    cat << 'EOF' > sensor_dummy.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    char* mode = getenv("DIAG_MODE");
    if (mode != NULL && mode[0] == '1') {
        // High load values that will cause 32-bit integer overflow when squared
        printf("40000\n50000\n60000\n");
    } else {
        // Output binary garbage to simulate proprietary encoded format
        unsigned char garbage[] = {0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03};
        fwrite(garbage, 1, sizeof(garbage), stdout);
    }
    return 0;
}
EOF

    gcc sensor_dummy.c -o sensor_dummy
    rm sensor_dummy.c

    # Create the buggy agent.cpp
    cat << 'EOF' > agent.cpp
#include <iostream>
#include <vector>
#include <cmath>
#include <string>
#include <cstdlib>

int main() {
    // BUG 1: The environment variable DIAG_MODE=1 needs to be set to get plaintext output.
    // The user should either set it in the shell or add: setenv("DIAG_MODE", "1", 1);

    FILE* fp = popen("./sensor_dummy", "r");
    if (!fp) {
        std::cerr << "Failed to run sensor" << std::endl;
        return 1;
    }

    std::vector<int> readings;
    char buffer[256];
    while (fgets(buffer, sizeof(buffer), fp) != nullptr) {
        try {
            int val = std::stoi(buffer);
            readings.push_back(val);
        } catch (...) {
            std::cerr << "Error parsing output as integer. Did you configure the sensor correctly?" << std::endl;
            pclose(fp);
            return 1;
        }
    }
    pclose(fp);

    if (readings.empty()) {
        std::cerr << "No readings captured." << std::endl;
        return 1;
    }

    // BUG 2: 32-bit integer overflow.
    // 40000^2 + 50000^2 + 60000^2 = 1.6B + 2.5B + 3.6B = 7.7B
    // 7.7B > 2.14B (max 32-bit signed int). sum_sq needs to be long long or double.
    int sum_sq = 0; 
    for (int val : readings) {
        sum_sq += val * val;
    }

    double mean_sq = static_cast<double>(sum_sq) / readings.size();
    double rms = std::sqrt(mean_sq);

    std::cout << "RMS: " << std::fixed << rms << std::endl;
    return 0;
}
EOF

    chmod +x sensor_dummy

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
