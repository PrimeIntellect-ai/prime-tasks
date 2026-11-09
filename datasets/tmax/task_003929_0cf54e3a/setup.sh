#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc g++ git binutils
pip3 install pytest numpy

useradd -m -s /bin/bash user || true

# Create the legacy oracle
mkdir -p /app
cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char* key = getenv("ORACLE_KEY");
    if (!key || strcmp(key, "KEY_A9F3B2C8D7E1") != 0) {
        fprintf(stderr, "Invalid or missing ORACLE_KEY\n");
        return 1;
    }
    double val;
    while (scanf("%lf", &val) == 1) {
        val = val * 3.141592653589793;
        for (int i = 0; i < 50; i++) {
            val = val - (val * 0.01);
        }
        printf("%.10f\n", val);
    }
    return 0;
}
EOF
gcc -O2 /tmp/oracle.c -o /app/legacy_oracle
strip /app/legacy_oracle
rm /tmp/oracle.c

# Create the C++ repository
mkdir -p /home/user/sensor_pipeline
cd /home/user/sensor_pipeline
git init

cat << 'EOF' > main.cpp
#include <iostream>
#include <iomanip>
#include <cmath>

double process(double val) {
    val = val * 3.141592653589793;
    for (int i = 0; i < 50; i++) {
        val = val - (val * 0.01);
    }
    return val;
}

int main() {
    double val;
    while (std::cin >> val) {
        std::cout << std::fixed << std::setprecision(10) << process(val) << "\n";
    }
    return 0;
}
EOF
git add main.cpp
git config user.name "Dev" && git config user.email "dev@example.com"
git commit -m "Initial working implementation"

# Commit 2: Introduce precision loss
cat << 'EOF' > main.cpp
#include <iostream>
#include <iomanip>
#include <cmath>

float process(float val) {
    val = val * 3.14159f;
    for (int i = 0; i < 50; i++) {
        val = val - (val * 0.01f);
    }
    return val;
}

int main() {
    float val;
    while (std::cin >> val) {
        std::cout << std::fixed << std::setprecision(10) << process(val) << "\n";
    }
    return 0;
}
EOF
git add main.cpp
git commit -m "Optimize processing with float precision"

# Commit 3: Introduce infinite loop
cat << 'EOF' > main.cpp
#include <iostream>
#include <iomanip>
#include <cmath>

float process(float val) {
    val = val * 3.14159f;
    int i = 0;
    while (i != 50) {
        val = val - (val * 0.01f);
        if (val < 0) {
            // Bug: i is never incremented if val < 0, causing infinite loop
            val = 0;
            continue;
        }
        i++;
    }
    return val;
}

int main() {
    float val;
    while (std::cin >> val) {
        std::cout << std::fixed << std::setprecision(10) << process(val) << "\n";
    }
    return 0;
}
EOF
git add main.cpp
git commit -m "Add bounds checking"

echo "-5.0" > /home/user/sample_input.txt

chown -R user:user /home/user/sensor_pipeline
chown user:user /home/user/sample_input.txt
chmod -R 777 /home/user
