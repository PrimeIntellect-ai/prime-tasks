#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev
    pip3 install pytest PyJWT

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create dummy auth_daemon
    cat << 'EOF' > /tmp/auth_daemon.c
#include <stdio.h>
int main() {
    const char* secret = "SecretKey2023!@#";
    printf("Auth daemon running...\n");
    return 0;
}
EOF
    gcc -s -o /app/auth_daemon /tmp/auth_daemon.c
    rm /tmp/auth_daemon.c

    # Generate corpus
    cat << 'EOF' > /tmp/gen_corpus.py
import jwt
import os
import base64

key = "SecretKey2023!@#"

clean_dir = "/app/corpus/clean"
evil_dir = "/app/corpus/evil"

# Clean tokens
for i in range(5):
    token = jwt.encode({"user": f"user{i}", "role": "user"}, key, algorithm="HS256")
    with open(os.path.join(clean_dir, f"token_{i}.txt"), "w") as f:
        f.write(token)

# Evil tokens
# 1. role: admin
token_admin = jwt.encode({"user": "user1", "role": "admin"}, key, algorithm="HS256")
with open(os.path.join(evil_dir, "token_admin.txt"), "w") as f:
    f.write(token_admin)

# 2. invalid signature
token_invalid = jwt.encode({"user": "user1", "role": "user"}, "wrongkey", algorithm="HS256")
with open(os.path.join(evil_dir, "token_invalid.txt"), "w") as f:
    f.write(token_invalid)

# 3. alg: none (manual construction)
def b64url(s):
    return base64.urlsafe_b64encode(s.encode()).decode().rstrip('=')

header = '{"alg":"none","typ":"JWT"}'
payload = '{"user":"user1","role":"user"}'
token_none = f"{b64url(header)}.{b64url(payload)}."
with open(os.path.join(evil_dir, "token_none.txt"), "w") as f:
    f.write(token_none)

EOF
    python3 /tmp/gen_corpus.py
    rm /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
