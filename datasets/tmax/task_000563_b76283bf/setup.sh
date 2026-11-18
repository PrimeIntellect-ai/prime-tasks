#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make tar
    pip3 install pytest

    # Create required directories
    mkdir -p /app/vendor /app/corpus/clean /app/corpus/evil

    # Create dummy netlogger-1.2 source and tar it
    mkdir -p /tmp/netlogger-1.2/src
    cat << 'EOF' > /tmp/netlogger-1.2/src/main.cpp
#include <iostream>
#include <thread>
int main() {
    std::thread t([](){});
    t.join();
    std::cout << "Netlogger 1.2" << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > /tmp/netlogger-1.2/Makefile
netlogger: src/main.cpp
	g++ -std=c++11 src/main.cpp -o netlogger
EOF

    tar -czf /app/vendor/netlogger-1.2.tar.gz -C /tmp netlogger-1.2

    # Populate clean corpus
    cat << 'EOF' > /app/corpus/clean/clean1.log
[2023-10-01T12:00:00Z] 192.168.1.50:8080 CONNECT Connection established
[2023-10-01T12:00:01Z] 10.0.5.9:9000 DATA Payload received
EOF

    # Populate evil corpus
    cat << 'EOF' > /app/corpus/evil/evil1.log
[2023-10-01T12:00:02Z] 203.0.113.5:8080 CONNECT SPOOF attempt
[2023-10-01T12:00:03Z] 192.168.1.50:80 CONNECT Connection established
[2023-10-01T12:00:04Z] 8.8.8.8:9000 DATA Payload received
[2023-10-01T12:00:05Z] 10.0.5.9:9000 DATA MALFORMED packet
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
