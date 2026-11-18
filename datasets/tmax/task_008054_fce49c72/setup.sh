#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    python3 -c '
import os
import base64
import zlib
import hashlib

wordlist = ["apple", "banana", "cherry", "mango", "security", "hunter2", "password", "legacy"]
with open("/home/user/wordlist.txt", "w") as f:
    f.write("\n".join(wordlist) + "\n")

secret = "mango"

def b64url_nopad(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("utf-8")

def create_token(header_str, payload_str, sec):
    h = b64url_nopad(header_str.encode())
    p = b64url_nopad(payload_str.encode())
    sig_input = f"{h}.{p}.{sec}".encode()
    sig = hashlib.md5(sig_input).hexdigest()
    return f"{h}.{p}.{sig}"

header = "{\"alg\":\"md5\",\"typ\":\"cJWT\"}"
t1 = create_token(header, "{\"user\":\"test\",\"action\":\"login\"}", secret)
t2 = create_token(header, "{\"user\":\"guest\",\"action\":\"view\"}", secret)

logs = f"""[2023-10-01 10:00:01] INFO Connection established from 192.168.1.10
[2023-10-01 10:05:23] DEBUG Auth success for token: {t1}
[2023-10-01 10:10:45] INFO Processing request for test
[2023-10-01 10:15:12] DEBUG Auth success for token: {t2}
[2023-10-01 10:20:00] INFO Connection closed
"""
with open("/home/user/server_logs.txt", "w") as f:
    f.write(logs)

source_code = """
import hashlib
import base64

def verify_token(token, secret):
    try:
        header, payload, sig = token.split(".")
        expected_sig = hashlib.md5(f"{header}.{payload}.{secret}".encode()).hexdigest()
        return sig == expected_sig
    except Exception:
        return False
"""
compressed = zlib.compress(source_code.encode())
b64_encoded = base64.b64encode(compressed).decode("utf-8")

obfuscated_script = f"""import base64, zlib
exec(zlib.decompress(base64.b64decode("{b64_encoded}")))
"""
with open("/home/user/auth_logic.py", "w") as f:
    f.write(obfuscated_script)
'

    chmod -R 777 /home/user
