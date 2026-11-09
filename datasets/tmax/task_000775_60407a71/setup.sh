#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask redis

    apt-get install -y g++ libhiredis-dev nlohmann-json3-dev libcurl4-openssl-dev libcpp-httplib-dev redis-server curl

    mkdir -p /app

    cat << 'EOF' > /app/startup.sh
#!/bin/bash
redis-server --daemonize yes
sleep 1
python3 /app/populate_redis.py
python3 /app/validator.py &
EOF
    chmod +x /app/startup.sh

    cat << 'EOF' > /app/populate_redis.py
import redis
import json

r = redis.Redis(host='localhost', port=6379, db=0)
data = [
    {"id": 1, "text": "Hello world!"},
    {"id": 2, "text": "hello, World."}, 
    {"id": 3, "text": "A completely different text."},
    {"id": 4, "text": "hello world again"} 
]
for item in data:
    r.rpush('raw_dataset', json.dumps(item))
EOF

    cat << 'EOF' > /app/validator.py
from flask import Flask, request
import logging

app = Flask(__name__)
log = logging.getLogger('werkzeug')
log.setLevel(logging.ERROR)

@app.route('/validate', methods=['POST'])
def validate():
    if request.content_type != 'application/json':
        return "Bad Content-Type", 400
    data = request.get_json(silent=True)
    if not data or 'id' not in data or 'tokens' not in data:
        return "Bad Data", 400
    return "OK", 200

if __name__ == '__main__':
    app.run(port=8080, host='0.0.0.0')
EOF

    cat << 'EOF' > /app/reference_ids.json
[1, 3, 4]
EOF

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/cleaner.cpp
#include <iostream>
#include <string>
#include <vector>
#include <hiredis/hiredis.h>
#include <nlohmann/json.hpp>
#include <httplib.h>
#include <fstream>
#include <algorithm>
#include <cctype>
#include <set>

using json = nlohmann::json;

int main() {
    redisContext *c = redisConnect("127.0.0.1", 6379);
    if (c == NULL || c->err) {
        if (c) {
            std::cerr << "Error: " << c->errstr << std::endl;
            redisFree(c);
        } else {
            std::cerr << "Can't allocate redis context" << std::endl;
        }
        return 1;
    }

    httplib::Client cli("http://localhost:8080");
    std::ofstream out("/home/user/cleaned_dataset.jsonl", std::ios::app);

    while (true) {
        redisReply *reply = (redisReply *)redisCommand(c, "LPOP raw_dataset");
        if (reply == NULL || reply->type == REDIS_REPLY_NIL) {
            if (reply) freeReplyObject(reply);
            break;
        }

        std::string raw_str = reply->str;
        freeReplyObject(reply);

        json item = json::parse(raw_str);

        // TODO: Implement tokenization, deduplication, and schema enforcement

        json payload;
        payload["id"] = item["id"];
        // payload["tokens"] = ...

        // Bug: missing application/json content type
        auto res = cli.Post("/validate", payload.dump(), "text/plain");
        if (res && res->status == 200) {
            out << payload.dump() << "\n";
        }
    }

    redisFree(c);
    return 0;
}
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user
