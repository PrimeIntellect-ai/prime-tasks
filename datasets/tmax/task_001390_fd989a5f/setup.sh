#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    # Create the app directory
    mkdir -p /app/storage-monitor-1.0

    # Create buggy monitor.cpp
    cat << 'EOF' > /app/storage-monitor-1.0/monitor.cpp
#include <iostream>

int main() {
    int usage;
    while (std::cin >> usage) {
        if (usage < 1024) {
            std::cout << "OK\n";
        } else if (usage < 2048) {
            std::cout << "WARNING\n";
        } else if (usage > 2048) {
            std::cout << "CRITICAL\n";
        }
    }
    return 0;
}
EOF

    # Create buggy Makefile
    cat << 'EOF' > /app/storage-monitor-1.0/Makefile
CXXFLAGS=-DENV=PROD

storage-daemon: monitor.cpp
	$(CXX) $(CXXFLAGS) monitor.cpp -o storage-daemon
EOF

    # Create correct oracle source
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/oracle.cpp
#include <iostream>

int main() {
    int usage;
    while (std::cin >> usage) {
        if (usage < 1024) {
            std::cout << "OK\n";
        } else if (usage < 2048) {
            std::cout << "WARNING\n";
        } else {
            std::cout << "CRITICAL\n";
        }
    }
    return 0;
}
EOF

    # Compile oracle
    g++ -O3 /opt/oracle/oracle.cpp -o /opt/oracle/storage-daemon-ref
    strip /opt/oracle/storage-daemon-ref
    rm /opt/oracle/oracle.cpp

    # Create user
    useradd -m -s /bin/bash user || true

    # Ensure home permissions
    chmod -R 777 /home/user
