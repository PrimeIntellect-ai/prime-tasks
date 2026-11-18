#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang build-essential curl
pip3 install pytest

mkdir -p /home/user/legacy /home/user/c_src /home/user/src /home/user/bin /home/user/lib

cat << 'EOF' > /home/user/legacy/limiter.py
import json

# In-memory store for rate limiting
request_counts = {}
RATE_LIMIT = 3

def handle_request(payload_str):
    """
    Reference implementation:
    1. Parse JSON. Return 400 if invalid.
    2. Payload must contain 'user_id' and 'action'. Return 400 if missing.
    3. Check rate limit for the given 'user_id'. Max 3 requests allowed.
       Return 429 if exceeded.
    4. Otherwise return 200.
    """
    try:
        data = json.loads(payload_str)
    except Exception:
        return 400

    if "user_id" not in data or "action" not in data:
        return 400

    user_id = data["user_id"]

    current_count = request_counts.get(user_id, 0)
    if current_count >= RATE_LIMIT:
        return 429

    request_counts[user_id] = current_count + 1
    return 200
EOF

cat << 'EOF' > /home/user/c_src/filter.h
#ifndef FILTER_H
#define FILTER_H

int is_blocked(const char* ip);

#endif
EOF

cat << 'EOF' > /home/user/c_src/filter.c
#include "filter.h"
#include <string.h>

int is_blocked(const char* ip) {
    if (ip == NULL) return 0;
    // Hardcoded blacklist for testing
    if (strcmp(ip, "198.51.100.55") == 0) {
        return 1;
    }
    return 0;
}
EOF

cat << 'EOF' > /home/user/verify.sh
#!/bin/bash

if [ ! -f /home/user/test_success.log ]; then
    echo "test_success.log not found"
    exit 1
fi

cd /home/user
make clean
make build

export LD_LIBRARY_PATH=/home/user/lib:$LD_LIBRARY_PATH
/home/user/bin/server &
SERVER_PID=$!
sleep 2

# Test 403 Forbidden
RES=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://127.0.0.1:8080/api/action -H "X-Forwarded-For: 198.51.100.55" -d '{"user_id":"u1","action":"jump"}')
if [ "$RES" != "403" ]; then echo "Failed 403 test"; kill $SERVER_PID; exit 1; fi

# Test 400 Bad Request
RES=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://127.0.0.1:8080/api/action -d '{"action":"jump"}')
if [ "$RES" != "400" ]; then echo "Failed 400 test"; kill $SERVER_PID; exit 1; fi

# Test 200 OK
RES=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://127.0.0.1:8080/api/action -d '{"user_id":"u2","action":"jump"}')
if [ "$RES" != "200" ]; then echo "Failed 200 test"; kill $SERVER_PID; exit 1; fi

# Test Rate Limit (3 max)
curl -s -o /dev/null -X POST http://127.0.0.1:8080/api/action -d '{"user_id":"u2","action":"jump"}'
curl -s -o /dev/null -X POST http://127.0.0.1:8080/api/action -d '{"user_id":"u2","action":"jump"}'

# 4th request should be 429
RES=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://127.0.0.1:8080/api/action -d '{"user_id":"u2","action":"jump"}')
if [ "$RES" != "429" ]; then echo "Failed 429 test"; kill $SERVER_PID; exit 1; fi

kill $SERVER_PID
echo "PASS"
exit 0
EOF
chmod +x /home/user/verify.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
