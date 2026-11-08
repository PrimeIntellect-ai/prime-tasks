#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go gcc libssl-dev
    pip3 install pytest

    mkdir -p /app /var/log /usr/share/wordlists

    cat << 'EOF' > /app/legacy_auth.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <openssl/evp.h>

int main(int argc, char *argv[]) {
    if (argc != 4) {
        return 1;
    }
    char *username = argv[1];
    char *password = argv[2];
    long timestamp = atol(argv[3]);
    long time_window = timestamp / 60;

    char buffer[512];
    snprintf(buffer, sizeof(buffer), "%s:%s:%ld", username, password, time_window);

    EVP_MD_CTX *mdctx;
    const EVP_MD *md;
    unsigned char md_value[EVP_MAX_MD_SIZE];
    unsigned int md_len;

    md = EVP_md5();
    mdctx = EVP_MD_CTX_new();
    EVP_DigestInit_ex(mdctx, md, NULL);
    EVP_DigestUpdate(mdctx, buffer, strlen(buffer));
    EVP_DigestFinal_ex(mdctx, md_value, &md_len);
    EVP_MD_CTX_free(mdctx);

    for(unsigned int i = 0; i < md_len; i++) {
        printf("%02x", md_value[i]);
    }
    printf("\n");
    return 0;
}
EOF

    gcc -o /app/legacy_auth /app/legacy_auth.c -lcrypto -s
    rm /app/legacy_auth.c

    cat << 'EOF' > /usr/share/wordlists/rockyou-top500.txt
password
123456
123456789
qwerty
password123
admin
EOF

    cat << 'EOF' > /app/setup_data.py
import hashlib
import json

def gen_token(user, pwd, ts):
    s = f"{user}:{pwd}:{ts//60}"
    return hashlib.md5(s.encode()).hexdigest()

logs = [
    {"timestamp": 1600000000, "username": "alice", "password": "password"},
    {"timestamp": 1600000050, "username": "bob", "password": "123456"}
]

with open("/var/log/auth_headers.log", "w") as f:
    for l in logs:
        t = gen_token(l["username"], l["password"], l["timestamp"])
        f.write(json.dumps({"timestamp": l["timestamp"], "username": l["username"], "X-Auth-Token": t}) + "\n")

hidden_logs = [
    {"timestamp": 1600001000, "username": "charlie", "password": "admin"},
    {"timestamp": 1600001050, "username": "dave", "password": "qwerty"}
]

with open("/app/hidden_test_logs.log", "w") as f:
    for l in hidden_logs:
        t = gen_token(l["username"], l["password"], l["timestamp"])
        f.write(json.dumps({"timestamp": l["timestamp"], "username": l["username"], "X-Auth-Token": t}) + "\n")

with open("/app/hidden_wordlist.txt", "w") as f:
    f.write("admin\nqwerty\npassword\n")

with open("/app/expected_results.json", "w") as f:
    json.dump({"charlie": "admin", "dave": "qwerty"}, f)
EOF

    python3 /app/setup_data.py
    rm /app/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
