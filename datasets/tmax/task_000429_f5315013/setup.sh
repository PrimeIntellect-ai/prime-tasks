#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user/profiles

python3 -c '
import base64
import json
def enc(s):
    x = bytes([b ^ 0x5A for b in s.encode("utf-8")])
    return base64.b64encode(x).decode("utf-8")

payloads = [
    {"user":"root","role":"admin","uid":0},
    {"user":"alice","role":"user","uid":1001},
    {"user":"bob","role":"admin","uid":1002},
    {"user":"eve","role":"admin","uid":1005},
    {"user":"charlie","role":"user","uid":1003},
    {"user":"dave","role":"admin","uid":1004}
]
with open("/home/user/auth_dump.txt", "w") as f:
    for p in payloads:
        f.write(enc(json.dumps(p, separators=(",",":"))) + "\n")
'

touch /home/user/profiles/root.json
touch /home/user/profiles/alice.json
touch /home/user/profiles/bob.json
touch /home/user/profiles/eve.json
touch /home/user/profiles/charlie.json
touch /home/user/profiles/dave.json

chown -R user:user /home/user/profiles
chown user:user /home/user/auth_dump.txt

chmod -R 777 /home/user
chmod 644 /home/user/profiles/root.json
chmod 600 /home/user/profiles/alice.json
chmod 666 /home/user/profiles/bob.json
chmod 644 /home/user/profiles/eve.json
chmod 666 /home/user/profiles/charlie.json
chmod 777 /home/user/profiles/dave.json
