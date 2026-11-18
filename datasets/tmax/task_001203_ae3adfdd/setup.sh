#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server libhiredis-dev g++ valgrind strace gdb
pip3 install pytest

mkdir -p /home/user/src
mkdir -p /home/user/bin
mkdir -p /home/user/corpus/clean
mkdir -p /home/user/corpus/evil
mkdir -p /app

cat << 'EOF' > /home/user/src/log_processor.cpp
#include <iostream>
#include <string>
#include <regex>
#include <stdexcept>
#include <hiredis/hiredis.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

struct TimezoneContext {
    std::string raw_tz;
    int offset_minutes;
};

void process_log(const std::string& log_line, redisContext* redis) {
    std::regex tz_regex(R"("timezone":\s*"([^"]+)")");
    std::smatch match;
    if (!std::regex_search(log_line, match, tz_regex)) {
        return;
    }

    std::string tz = match[1];
    TimezoneContext* ctx = new TimezoneContext();
    ctx->raw_tz = tz;

    if (tz == "Z") {
        ctx->offset_minutes = 0;
    } else {
        std::regex offset_regex(R"(([+-])(\d{2}):(\d{2}))");
        std::smatch offset_match;
        if (!std::regex_match(tz, offset_match, offset_regex)) {
            // Memory leak here! No delete ctx;
            return;
        }

        int hours = std::stoi(offset_match[2]);
        int minutes = std::stoi(offset_match[3]);

        if (hours > 14 || minutes > 59) {
            // Memory leak here!
            return;
        }

        int total_offset = hours * 60 + minutes;
        if (offset_match[1] == "-") {
            total_offset = -total_offset;
        }
        ctx->offset_minutes = total_offset;
    }

    // Formula bug: applying offset incorrectly
    redisReply* reply = (redisReply*)redisCommand(redis, "INCR processed_logs");
    if (reply) freeReplyObject(reply);

    delete ctx;
}

int main() {
    redisContext* redis = redisConnect("127.0.0.1", 6379);
    if (redis == NULL || redis->err) {
        if (redis) redisFree(redis);
        return 1;
    }

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));

    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);

    bind(server_fd, (struct sockaddr*)&address, sizeof(address));
    listen(server_fd, 3);

    while (true) {
        int new_socket = accept(server_fd, nullptr, nullptr);
        if (new_socket < 0) continue;

        char buffer[1024] = {0};
        read(new_socket, buffer, 1024);
        process_log(std::string(buffer), redis);
        close(new_socket);
    }

    redisFree(redis);
    return 0;
}
EOF

cat << 'EOF' > /app/log_generator.py
import socket
import time
import json
import random

tzs = ["+05:30", "-11:00", "Z", "+15:00", "-04:60", "invalid"]

while True:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('127.0.0.1', 8080))
        payload = {"timestamp": int(time.time()), "timezone": random.choice(tzs)}
        s.sendall(json.dumps(payload).encode())
        s.close()
    except Exception:
        pass
    time.sleep(0.1)
EOF

cat << 'EOF' > /app/start_services.sh
#!/bin/bash
pkill redis-server
pkill log_processor
pkill -f log_generator.py

redis-server --daemonize yes
sleep 1
/home/user/bin/log_processor &
sleep 1
python3 /app/log_generator.py &
EOF
chmod +x /app/start_services.sh

for i in $(seq 1 100); do
    echo "{\"timezone\": \"+05:30\"}" > /home/user/corpus/clean/clean_$i.json
    echo "{\"timezone\": \"+15:00\"}" > /home/user/corpus/evil/evil_$i.json
done

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
