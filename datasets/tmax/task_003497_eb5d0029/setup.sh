#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ wget espeak
pip3 install pytest

mkdir -p /app/include
mkdir -p /app/corpus/clean
mkdir -p /app/corpus/evil

wget -O /app/include/json.hpp https://github.com/nlohmann/json/releases/download/v3.11.2/json.hpp

espeak -w /app/auth_token.wav "crimson typhoon"

python3 -c '
import json
import os

valid = {"auth_token": "crimson typhoon", "target_path": "/var/conf/valid"}
evil1 = {"auth_token": "blue typhoon", "target_path": "/var/conf/valid"}
evil2 = {"auth_token": "crimson typhoon", "target_path": "/var/conf/../../etc/passwd"}

with open("/app/corpus/clean/valid1.json", "w") as f:
    json.dump(valid, f)

with open("/app/corpus/clean/valid2.json", "wb") as f:
    f.write(b"\xff\xfe" + json.dumps(valid).encode("utf-16le"))

with open("/app/corpus/evil/wrong_token.json", "w") as f:
    json.dump(evil1, f)

with open("/app/corpus/evil/path_traversal.json", "w") as f:
    json.dump(evil2, f)

with open("/app/corpus/evil/invalid.json", "w") as f:
    f.write("{\"auth_token\": \"crimson typhoon\", \"target_path\": \"/var/conf/valid\"")
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
