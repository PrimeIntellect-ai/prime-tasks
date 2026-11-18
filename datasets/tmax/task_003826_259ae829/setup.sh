#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make redis-server
    pip3 install pytest flask redis

    mkdir -p /app/core
    mkdir -p /app/aggregator/src
    mkdir -p /app/dashboard

    # Create mock core dump
    echo "Some binary garbage POISON_PILL_ERR_DEADBEEF_90210 more garbage" > /app/core/core.aggregator

    # Create C++ source with deadlock and blocking IO
    cat << 'EOF' > /app/aggregator/src/server.cpp
#include <iostream>
#include <string>
#include <mutex>
#include <thread>
#include <vector>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

std::mutex mtx;

void process_metric(const std::string& metric) {
    mtx.lock();
    // Simulate blocking IO
    usleep(100000);
    // Deliberate deadlock: no unlock
}

int main() {
    std::cout << "Aggregator started" << std::endl;
    while(true) {
        sleep(1);
    }
    return 0;
}
EOF

    # Create aggregator config
    cat << 'EOF' > /app/aggregator/config.ini
[Server]
ingestion_port=8082
query_port=8083
EOF

    # Create Makefile
    cat << 'EOF' > /app/aggregator/Makefile
server: src/server.cpp
	g++ -O2 -pthread -o server src/server.cpp
EOF

    # Create dashboard config
    cat << 'EOF' > /app/dashboard/config.json
{
    "aggregator_host": "127.0.0.1",
    "aggregator_port": 8083,
    "redis_host": "127.0.0.1",
    "redis_port": 6380
}
EOF

    # Create dashboard app
    cat << 'EOF' > /app/dashboard/app.py
import json
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/api/stats')
def stats():
    return jsonify({"DEV_1": {"count": 0, "sum": 0}})

if __name__ == '__main__':
    with open('/app/dashboard/config.json') as f:
        config = json.load(f)
    app.run(host='127.0.0.1', port=9001)
EOF

    # Create start script
    cat << 'EOF' > /app/start_all.sh
#!/bin/bash
redis-server --port 6379 --daemonize yes
cd /app/aggregator && ./server &
python3 /app/dashboard/app.py &
wait
EOF
    chmod +x /app/start_all.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
