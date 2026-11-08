#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc git redis-server curl
pip3 install pytest flask redis requests

mkdir -p /home/user/app/api
mkdir -p /home/user/app/ingester
mkdir -p /home/user/app/data

cat << 'EOF' > /home/user/app/api/server.py
from flask import Flask, request, jsonify
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/ingest', methods=['POST'])
def ingest():
    if request.headers.get('X-API-Key') != 'd34db33f_s3cr3t99':
        return jsonify({"error": "Unauthorized"}), 401
    r.incr('processed_count')
    return jsonify({"status": "ok"})

@app.route('/metrics', methods=['GET'])
def metrics():
    count = r.get('processed_count')
    return jsonify({"processed_count": int(count) if count else 0})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

cat << 'EOF' > /home/user/app/ingester/ingester.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
// Missing curl header to cause compilation error

#define MAGIC 0xDEADBEEF

int main() {
    FILE *fp = fopen("../data/transactions.wal", "rb");
    if (!fp) return 1;

    char *api_secret = getenv("API_SECRET");
    if (!api_secret) {
        printf("Missing API_SECRET\n");
        return 1;
    }

    unsigned int magic;
    unsigned int size;

    while (fread(&magic, sizeof(int), 1, fp) == 1) {
        if (magic != MAGIC) {
            break;
        }
        if (fread(&size, sizeof(int), 1, fp) != 1) break;

        char *payload = malloc(size + 1);
        if (fread(payload, 1, size, fp) != size) break;
        payload[size] = '\0';

        CURL *curl = curl_easy_init();
        if(curl) {
            curl_easy_setopt(curl, CURLOPT_URL, "http://localhost:5000/ingest");
            struct curl_slist *headers = NULL;
            char auth_header[256];
            snprintf(auth_header, sizeof(auth_header), "X-API-Key: %s", api_secret);
            headers = curl_slist_append(headers, auth_header);
            headers = curl_slist_append(headers, "Content-Type: application/json");
            curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
            curl_easy_setopt(curl, CURLOPT_POSTFIELDS, payload);
            curl_easy_perform(curl);
            curl_slist_free_all(headers);
            curl_easy_cleanup(curl);
        }

        free(payload);
    }
    fclose(fp);
    return 0;
}
EOF

cat << 'EOF' > /home/user/generate_wal.py
import struct
import random

with open('/home/user/app/data/transactions.wal', 'wb') as f:
    for i in range(1000):
        f.write(struct.pack('<I', 0xDEADBEEF))
        payload = b'{"amount": 100}'
        f.write(struct.pack('<I', len(payload)))
        f.write(payload)

        if i < 50:
            f.write(struct.pack('<I', 0xDEADBEEF))
            f.write(struct.pack('<I', 0xFFFFFFFF))
            f.write(b'GARBAGE')
EOF
python3 /home/user/generate_wal.py
rm /home/user/generate_wal.py

cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
python3 /home/user/app/api/server.py &
sleep 2
EOF
chmod +x /home/user/app/start_services.sh

cat << 'EOF' > /home/user/evaluate_yield.py
import requests, sys
try:
    resp = requests.get("http://localhost:5000/metrics").json()
    valid_processed = resp.get("processed_count", 0)
    yield_rate = valid_processed / 1000.0
    print(yield_rate)
except Exception as e:
    print(0.0)
EOF

cd /home/user/app/ingester
git init
git config user.email "dev@local"
git config user.name "Dev"
echo 'API_SECRET=d34db33f_s3cr3t99' > secret.txt
git add secret.txt
git commit -m "Add secret"
rm secret.txt
git add .
git commit -a -m "Remove secret"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
