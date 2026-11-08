#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils sudo
    pip3 install pytest

    # Create groups and users
    groupadd wheel || true
    useradd -m -s /bin/bash devuser || true
    useradd -m -s /bin/bash adminuser || true
    useradd -m -s /bin/bash wheeluser || true

    usermod -aG sudo adminuser
    usermod -aG wheel wheeluser

    # Create token checker binary
    mkdir -p /app
    cat << 'EOF' > /app/check_token.c
#include <stdio.h>
#include <string.h>
int main(int argc, char *argv[]) {
    if(argc != 2) return 1;
    if(strlen(argv[1]) < 5) return 1;
    int sum = 0;
    for(int i=0; i<strlen(argv[1]); i++){
        sum += argv[1][i];
    }
    if(sum % 10 == 0) return 0;
    return 1;
}
EOF
    gcc /app/check_token.c -o /app/check_token
    strip /app/check_token
    rm /app/check_token.c

    # Generate corpora
    mkdir -p /home/user/corpora/clean /home/user/corpora/evil /eval/clean_corpus /eval/evil_corpus

    python3 -c '
import json
import os

def write_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f)

valid_token = "aaaaf" # 97*4 + 102 = 490
invalid_token = "aaaae" # 489

base_req = {
    "username": "devuser",
    "vnc_display": 50,
    "env": {"TEST": "value"},
    "vm_token": valid_token
}

# Generate clean
for i in range(20):
    req = base_req.copy()
    req["vnc_display"] = i + 1
    write_json(f"/eval/clean_corpus/clean_{i}.json", req)
    if i < 5:
        write_json(f"/home/user/corpora/clean/clean_{i}.json", req)

# Generate evil
evils = [
    {"username": "adminuser"}, # sudo
    {"username": "wheeluser"}, # wheel
    {"username": "nonexistent"}, # doesn'\''t exist
    {"vnc_display": 0}, # < 1
    {"vnc_display": 100}, # > 99
    {"env": {"MY_PRELOAD": "1"}}, # contains PRELOAD
    {"env": {"BASH_ENV_VAR": "1"}}, # contains BASH_ENV
    {"vm_token": invalid_token}, # invalid token
    {"vm_token": "a"}, # too short
]

for i, evil_mod in enumerate(evils * 3): # Make at least 20
    req = base_req.copy()
    req.update(evil_mod)
    write_json(f"/eval/evil_corpus/evil_{i}.json", req)
    if i < 5:
        write_json(f"/home/user/corpora/evil/evil_{i}.json", req)
'

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
