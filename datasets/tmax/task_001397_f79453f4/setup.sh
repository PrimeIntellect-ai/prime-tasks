#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true

    python3 -c '
import os
import json
import base64
from cryptography.fernet import Fernet

def encode_jwt(header, payload, sig=""):
    h = base64.urlsafe_b64encode(json.dumps(header).encode()).decode().rstrip("=")
    p = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
    if sig:
        return f"{h}.{p}.{sig}"
    return f"{h}.{p}."

key = Fernet.generate_key()
with open("/home/user/rotation_key.key", "wb") as f:
    f.write(key)

logs = [
    {
        "method": "GET",
        "path": "/api/data",
        "headers": {
            "Authorization": "Bearer " + encode_jwt({"alg": "HS256", "typ": "JWT"}, {"username": "alice"}, "fakesig123"),
            "User-Agent": "Mozilla/5.0"
        }
    },
    {
        "method": "POST",
        "path": "/api/admin",
        "headers": {
            "Authorization": "Bearer " + encode_jwt({"alg": "none", "typ": "JWT"}, {"username": "sysadmin"}),
            "User-Agent": "curl/7.68.0"
        }
    },
    {
        "method": "GET",
        "path": "/api/reports",
        "headers": {
            "Authorization": "Bearer " + encode_jwt({"alg": "RS256", "typ": "JWT"}, {"username": "bob"}, "fakesig456"),
            "User-Agent": "Mozilla/5.0"
        }
    },
    {
        "method": "DELETE",
        "path": "/api/users/1",
        "headers": {
            "Authorization": "Bearer " + encode_jwt({"alg": "None", "typ": "JWT"}, {"username": "db_service"}),
            "User-Agent": "python-requests/2.25.1"
        }
    },
    {
        "method": "POST",
        "path": "/api/admin",
        "headers": {
            "Authorization": "Bearer " + encode_jwt({"alg": "NONE", "typ": "JWT"}, {"username": "sysadmin"}),
            "User-Agent": "curl/7.68.0"
        }
    }
]

with open("/home/user/access.log", "w") as f:
    for log in logs:
        f.write(json.dumps(log) + "\n")
'

    chmod -R 777 /home/user
