#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git g++
    pip3 install pytest

    mkdir -p /home/user/app
    cd /home/user/app

    git init
    git config user.email "oncall@example.com"
    git config user.name "OnCall Engineer"

    cat << 'EOF' > calc.cpp
#include <iostream>
#include <cmath>
#include <string>
#include <stdexcept>
#include <iomanip>

int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <token>" << std::endl;
        return 1;
    }
    std::string token = argv[1];

    double base = 0.0;
    for (char c : token) {
        base += c;
    }

    // Accumulate fine-grained sensor data
    double accumulator = base;
    for(int i=0; i<10000000; ++i) {
        accumulator += 0.0000001; 
    }

    double result = accumulator;
    double expected = base + 1.0;

    if (std::abs(result - expected) > 0.1) {
        throw std::domain_error("System unstable: Critical precision loss detected. Values diverged.");
    }

    std::cout << std::fixed << std::setprecision(5) << result << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > run.sh
#!/bin/bash
./calc super_secret_production_key_9921
EOF
    chmod +x run.sh

    git add calc.cpp run.sh
    git commit -m "Initial commit: Add calculation engine and run script"

    # Commit 2: Introduce precision loss
    sed -i 's/double accumulator = base;/float accumulator = base;/g' calc.cpp
    sed -i 's/accumulator += 0.0000001;/accumulator += 0.0000001f;/g' calc.cpp
    git add calc.cpp
    git commit -m "Optimize memory usage in hot loop"

    # Commit 3: Remove secret
    sed -i 's/super_secret_production_key_9921/REDACTED/g' run.sh
    git add run.sh
    git commit -m "Security: Remove hardcoded token from run script"

    g++ -O2 calc.cpp -o calc

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
