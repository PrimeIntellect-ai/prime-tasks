#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential netcat-openbsd
    pip3 install pytest

    # Create directories
    mkdir -p /app/telemetry_env/src
    mkdir -p /app/telemetry_env/bin
    mkdir -p /app/telemetry_env/corpora/clean
    mkdir -p /app/telemetry_env/corpora/evil
    mkdir -p /opt/libser/v1
    mkdir -p /opt/libser/v2

    # Create generator script
    cat << 'EOF' > /app/telemetry_env/generator.sh
#!/bin/bash
for f in /app/telemetry_env/corpora/clean/* /app/telemetry_env/corpora/evil/*; do
    cat "$f" | nc -u -w1 localhost 8080
    sleep 0.1
done
EOF
    chmod +x /app/telemetry_env/generator.sh

    # Create sink script
    cat << 'EOF' > /app/telemetry_env/sink.sh
#!/bin/bash
nc -l -p 9090
EOF
    chmod +x /app/telemetry_env/sink.sh

    # Create Makefile with intentional bad path
    cat << 'EOF' > /app/telemetry_env/src/Makefile
CXX = g++
CXXFLAGS = -I/opt/libser/v1 -std=c++17 -pthread
LDFLAGS = -lpthread

all:
	$(CXX) $(CXXFLAGS) ingestor.cpp -o ../bin/telemetry_ingestor $(LDFLAGS)
EOF

    # Create ingestor.cpp with intentional bugs
    cat << 'EOF' > /app/telemetry_env/src/ingestor.cpp
#include <iostream>
#include <string>
#include <vector>
#include <thread>
#include <mutex>
#include <queue>

// Intentional: Shared unlocked queue (race condition)
std::queue<std::string> payload_queue;

void worker() {
    while (true) {
        if (!payload_queue.empty()) {
            std::string payload = payload_queue.front();
            payload_queue.pop();
            // Process payload...
        }
    }
}

int main() {
    std::cout << "Starting telemetry ingestor on UDP 8080..." << std::endl;
    std::thread t1(worker);
    std::thread t2(worker);

    t1.join();
    t2.join();
    return 0;
}
EOF

    # Generate corpora
    for i in $(seq 1 50); do
        echo "{\"id\": \"clean_$i\", \"data\": \"normal telemetry data\"}" > /app/telemetry_env/corpora/clean/payload_$i.json
        echo "{\"id\": \"evil_$i\", \"data\": \"../../etc/passwd $(whoami)\"}" > /app/telemetry_env/corpora/evil/payload_$i.json
    done

    # Set permissions for app directory
    chmod -R 777 /app
    chmod -R 777 /opt/libser

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
