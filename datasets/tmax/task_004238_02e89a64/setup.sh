#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
pip3 install pytest

mkdir -p /app/corpus/clean /app/corpus/evil

cat << 'EOF' > /tmp/auth_svc.c
#include <stdio.h>
#include <string.h>

int validate_token(const char* header) {
    if (strstr(header, "\"alg\": \"none\"") != NULL || 
        strstr(header, "\"alg\": \"NONE\"") != NULL ||
        strstr(header, "\"alg\": \"debug\"") != NULL) {
        return 1;
    }
    if (strstr(header, "\"alg\": \"HS256\"") != NULL) {
        return 2;
    }
    return 0;
}

int main(int argc, char** argv) {
    if (argc > 1) {
        return validate_token(argv[1]);
    }
    return 0;
}
EOF

gcc -s -static /tmp/auth_svc.c -o /app/auth_svc
rm /tmp/auth_svc.c

python3 -c '
import base64
import json

def encode(d):
    return base64.urlsafe_b64encode(json.dumps(d).encode()).decode()

clean = []
for i in range(50):
    h = encode({"alg": "HS256"})
    p = encode({"user": f"user{i}"})
    clean.append(f"{h}.{p}.signature")

evil = []
algs = ["none", "NONE", "debug"]
for i in range(50):
    h = encode({"alg": algs[i % 3]})
    p = encode({"user": "admin", "admin": True})
    evil.append(f"{h}.{p}.")

with open("/app/corpus/clean/tokens.txt", "w") as f:
    f.write("\n".join(clean))

with open("/app/corpus/evil/tokens.txt", "w") as f:
    f.write("\n".join(evil))
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
