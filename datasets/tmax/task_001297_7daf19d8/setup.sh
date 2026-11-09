#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip \
        gcc make libhiredis-dev redis-server git tshark \
        && rm -rf /var/lib/apt/lists/*

    pip3 install --default-timeout=100 pytest redis scapy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/docs
    cd /home/user/app

    # Create config.h and git repo
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"

    cat << 'EOF' > config.h
#ifndef CONFIG_H
#define CONFIG_H

#define REDIS_PASS "s3cr3t_w3ath3r_p4ss"
#define REDIS_HOST "127.0.0.1"
#define REDIS_PORT 6379

#endif
EOF

    git add config.h
    git commit -m "Initial commit with config"

    cat << 'EOF' > config.h
#ifndef CONFIG_H
#define CONFIG_H

#define REDIS_PASS "PLACEHOLDER"
#define REDIS_HOST "127.0.0.1"
#define REDIS_PORT 6379

#endif
EOF

    git add config.h
    git commit -m "Remove sensitive password"

    # Create ingest.c (buggy)
    cat << 'EOF' > ingest.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <hiredis/hiredis.h>
#include "config.h"

// Missing includes: <time.h>, <arpa/inet.h>

#pragma pack(push, 1)
struct Packet {
    uint32_t timestamp;
    uint32_t sensor_id;
    float temp;
};
#pragma pack(pop)

int main() {
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in serv_addr;
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(8081);
    // Missing inet_pton or similar, assuming localhost for now
    serv_addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        perror("Connection failed");
        return 1;
    }

    struct Packet pkt;
    while (1) {
        int n = read(sock, &pkt, sizeof(pkt));
        if (n <= 0) break;

        // Bug 4: Timezone bug (incorrectly rejecting packets)
        // Assume time(NULL) is UTC. The bug shifts it.
        time_t now = time(NULL);
        if (pkt.timestamp < now - 36000 || pkt.timestamp > now + 36000) {
            // Rejecting
            continue;
        }

        // Bug 5: Performance issue, connecting inside the loop
        redisContext *c = redisConnect(REDIS_HOST, REDIS_PORT);
        if (c == NULL || c->err) {
            if (c) redisFree(c);
            continue;
        }
        redisReply *auth_reply = redisCommand(c, "AUTH %s", REDIS_PASS);
        freeReplyObject(auth_reply);

        // Bug 3: Endianness not handled
        char json[256];
        snprintf(json, sizeof(json), "{\"timestamp\": %u, \"sensor_id\": %u, \"temp\": %f}",
                 pkt.timestamp, pkt.sensor_id, pkt.temp);

        redisReply *reply = redisCommand(c, "RPUSH sensor_data %s", json);
        if (reply) freeReplyObject(reply);

        redisFree(c);
    }
    close(sock);
    return 0;
}
EOF

    # Create Makefile (buggy)
    cat << 'EOF' > Makefile
all: ingest

ingest: ingest.c
	gcc -O2 -Wall ingest.c -o ingest
	# Missing -lhiredis

clean:
	rm -f ingest
EOF

    # Create start_services.sh
    cat << 'EOF' > start_services.sh
#!/bin/bash
redis-server --port 6379 --requirepass "s3cr3t_w3ath3r_p4ss" --daemonize yes
python3 /home/user/app/sensor_simulator.py &
EOF
    chmod +x start_services.sh

    # Create sensor_simulator.py
    cat << 'EOF' > sensor_simulator.py
import socket
import struct
import time
import random

def start_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', 8081))
    server.listen(1)

    while True:
        conn, addr = server.accept()
        try:
            while True:
                ts = int(time.time())
                sensor_id = random.randint(1, 100)
                temp = random.uniform(10.0, 30.0)
                # Big Endian
                data = struct.pack(">IIf", ts, sensor_id, temp)
                conn.sendall(data)
                # No sleep, high throughput
        except Exception:
            pass
        finally:
            conn.close()

if __name__ == "__main__":
    start_server()
EOF

    # Create benchmark.py
    cat << 'EOF' > benchmark.py
import time
import subprocess
import redis
import json

def run_benchmark():
    subprocess.run(["/home/user/app/start_services.sh"], check=True)
    time.sleep(1)

    r = redis.Redis(host='127.0.0.1', port=6379, password='s3cr3t_w3ath3r_p4ss')
    r.delete('sensor_data')

    p = subprocess.Popen(["/home/user/app/ingest"])
    time.sleep(3)
    p.terminate()
    p.wait()

    count = r.llen('sensor_data')
    print(count / 3.0)

    # Check correctness
    if count > 0:
        item = r.lpop('sensor_data')
        data = json.loads(item)
        if not (1 <= data.get('sensor_id', 0) <= 100):
            print("Invalid sensor_id")
            return
        if not (10.0 <= data.get('temp', 0.0) <= 30.0):
            print("Invalid temp")
            return

if __name__ == "__main__":
    run_benchmark()
EOF

    # Generate capture.pcap
    cat << 'EOF' > gen_pcap.py
from scapy.all import *
import struct
import time

ts = int(time.time())
payload = struct.pack(">IIf", ts, 42, 23.5)
pkt = IP(dst="127.0.0.1")/TCP(dport=8081)/Raw(load=payload)
wrpcap('/home/user/app/docs/capture.pcap', [pkt])
EOF
    python3 gen_pcap.py
    rm gen_pcap.py

    chown -R user:user /home/user/app
    chmod -R 777 /home/user
