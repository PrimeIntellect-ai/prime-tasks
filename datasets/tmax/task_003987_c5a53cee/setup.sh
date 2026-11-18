#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nginx logrotate binutils
    pip3 install pytest

    # Create the oracle binary
    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.cpp
#include <iostream>
#include <cstdlib>
#include <iomanip>

int main(int argc, char* argv[]) {
    if (argc != 3) {
        std::cerr << "Usage: " << argv[0] << " <request_rate> <allocation_units>\n";
        return 1;
    }
    double request_rate = std::atof(argv[1]);
    double allocation_units = std::atof(argv[2]);

    if (allocation_units < 1 || allocation_units > 100) {
        // Just proceed with the math, or clamp it, but prompt says 1-100 is expected.
    }

    double latency = (request_rate * 500.0) / (allocation_units * allocation_units);
    double cost = (allocation_units * 2.5) + (request_rate * 0.01);

    // Output format: Latency: <L> ms, Cost: $<C>
    std::cout << std::fixed << std::setprecision(2);
    std::cout << "Latency: " << latency << " ms, Cost: $" << cost << "\n";
    return 0;
}
EOF

    g++ -O2 /tmp/oracle.cpp -o /app/pricing_oracle
    strip /app/pricing_oracle
    chmod 755 /app/pricing_oracle
    rm /tmp/oracle.cpp

    # Create user
    useradd -m -s /bin/bash user || true

    # Create initial files
    cat << 'EOF' > /home/user/traffic.csv
endpoint_path,request_rate
/api/v1/users,500
/api/v1/products,1200
/api/v1/orders,850
/api/v2/catalog,3000
EOF

    # Create logs directory
    mkdir -p /home/user/logs

    # Ensure permissions
    chmod -R 777 /home/user
