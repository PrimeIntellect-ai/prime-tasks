#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server redis-tools g++ curl
    pip3 install pytest flask redis

    mkdir -p /home/user/workspace
    mkdir -p /opt/oracle

    cat << 'EOF' > /home/user/workspace/gateway.py
from flask import Flask, request
import struct
import redis

app = Flask(__name__)
r = redis.Redis(host='127.0.0.1', port=6379, db=0)

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.json
    payload = struct.pack('<BIf', data['sensor_id'], data['timestamp'], data['value'])
    r.rpush('raw_telemetry', payload)
    return "OK", 200

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /home/user/workspace/worker.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <unordered_map>
#include <string>

struct Record {
    uint8_t sensor_id;
    uint32_t timestamp;
    float value;
};

struct Stats {
    int count = 0;
    double sum = 0.0;
    double sum_sq = 0.0;
};

int main(int argc, char** argv) {
    if (argc >= 4 && std::string(argv[1]) == "--file-mode") {
        std::ifstream in(argv[2], std::ios::binary);
        std::ofstream out(argv[3], std::ios::binary);

        std::unordered_map<uint8_t, Stats> stats;
        Record r;
        // Naive variance calculation
        while (in.read(reinterpret_cast<char*>(&r), 9)) {
            Stats& s = stats[r.sensor_id];
            s.count++;
            s.sum += r.value;
            s.sum_sq += r.value * r.value;
        }

        for (auto& kv : stats) {
            uint8_t id = kv.first;
            float var = (kv.second.count > 1) ? ((kv.second.sum_sq - (kv.second.sum * kv.second.sum)/kv.second.count) / (kv.second.count - 1)) : 0.0f;
            out.write(reinterpret_cast<const char*>(&id), sizeof(id));
            out.write(reinterpret_cast<const char*>(&var), sizeof(var));
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > /opt/oracle/oracle.cpp
#include <iostream>
#include <fstream>
#include <vector>
#include <unordered_map>
#include <string>

#pragma pack(push, 1)
struct Record {
    uint8_t sensor_id;
    uint32_t timestamp;
    float value;
};
#pragma pack(pop)

struct Stats {
    int count = 0;
    double mean = 0.0;
    double M2 = 0.0;
};

int main(int argc, char** argv) {
    if (argc >= 4 && std::string(argv[1]) == "--file-mode") {
        std::ifstream in(argv[2], std::ios::binary);
        std::ofstream out(argv[3], std::ios::binary);

        std::unordered_map<uint8_t, Stats> stats;
        Record r;
        while (in.read(reinterpret_cast<char*>(&r), sizeof(r))) {
            Stats& s = stats[r.sensor_id];
            s.count++;
            double delta = r.value - s.mean;
            s.mean += delta / s.count;
            double delta2 = r.value - s.mean;
            s.M2 += delta * delta2;
        }

        for (auto& kv : stats) {
            uint8_t id = kv.first;
            float var = (kv.second.count > 1) ? (kv.second.M2 / (kv.second.count - 1)) : 0.0f;
            out.write(reinterpret_cast<const char*>(&id), sizeof(id));
            out.write(reinterpret_cast<const char*>(&var), sizeof(var));
        }
    }
    return 0;
}
EOF

    g++ -O3 -o /opt/oracle/worker_oracle /opt/oracle/oracle.cpp
    rm /opt/oracle/oracle.cpp

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/workspace
    chmod -R 777 /home/user
