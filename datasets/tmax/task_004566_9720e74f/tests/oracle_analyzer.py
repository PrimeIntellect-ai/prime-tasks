#!/usr/bin/env python3
import sys, hashlib, base64

if len(sys.argv) != 2:
    sys.exit(1)

try:
    raw_bytes = bytes.fromhex(sys.argv[1])
except ValueError:
    print("ERR_DECODE")
    sys.exit(0)

try:
    http_text = raw_bytes.decode('utf-8')
except UnicodeDecodeError:
    print("ERR_DECODE")
    sys.exit(0)

lines = http_text.split('\r\n')
session = None
cert = None

for line in lines:
    if line.lower().startswith('cookie:'):
        parts = line[7:].split(';')
        for p in parts:
            p = p.strip()
            if p.startswith('session='):
                session = p[8:]
    elif line.lower().startswith('x-cert-chain:'):
        cert = line[13:].strip()

if not session or not cert:
    print("ERR_MISSING")
    sys.exit(0)

if "CN=Admin" not in cert or not hashlib.md5(cert.encode()).hexdigest().endswith('f'):
    print("ERR_CERT")
    sys.exit(0)

try:
    enc_bytes = base64.b64decode(session)
except Exception:
    print("ERR_B64")
    sys.exit(0)

dec_bytes = bytes([b ^ 85 for b in enc_bytes])
try:
    dec_text = dec_bytes.decode('utf-8')
except Exception:
    print("ERR_AUTH")
    sys.exit(0)

if dec_text.startswith("SECURE_DEV_"):
    print(f"SUCCESS:{dec_text}")
else:
    print("ERR_AUTH")
