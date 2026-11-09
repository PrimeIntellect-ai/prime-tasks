#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak openssl
    pip3 install pytest

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate audio
    espeak -w /app/incident_report.wav "To properly audit these logs, your script must check three things. First, extract the X-Upload-Path header, which is base64 encoded. Decode it and flag it as EVIL if it contains the string dot dot slash or its URL encoded equivalent. Second, extract the base64 encoded certificate from the X-Client-Cert header, decode it into a PEM format, and verify it against our trusted_ca.pem; flag it if verification fails. Third, inspect the HTTP cookies. If the session_token cookie begins with the prefix GUEST_ , flag the request as EVIL immediately."

    # Generate certificates
    cd /app
    openssl req -x509 -newkey rsa:2048 -keyout trusted_ca.key -out trusted_ca.pem -days 365 -nodes -subj "/CN=Trusted CA"
    openssl req -x509 -newkey rsa:2048 -keyout untrusted_ca.key -out untrusted_ca.pem -days 365 -nodes -subj "/CN=Untrusted CA"

    # Python script to generate the corpora
    cat << 'EOF' > /app/generate_corpus.py
import os
import base64

def gen_cert(ca_key, ca_pem, name):
    os.system(f"openssl req -newkey rsa:2048 -keyout {name}.key -out {name}.csr -nodes -subj '/CN={name}' 2>/dev/null")
    os.system(f"openssl x509 -req -in {name}.csr -CA {ca_pem} -CAkey {ca_key} -CAcreateserial -out {name}.crt -days 365 2>/dev/null")
    with open(f"{name}.crt", "rb") as f:
        return base64.b64encode(f.read()).decode('utf-8')

trusted_cert_b64 = gen_cert("trusted_ca.key", "trusted_ca.pem", "trusted_client")
untrusted_cert_b64 = gen_cert("untrusted_ca.key", "untrusted_ca.pem", "untrusted_client")

def write_req(path, filename, cert_b64, upload_path, session_token):
    upload_path_b64 = base64.b64encode(upload_path.encode('utf-8')).decode('utf-8')
    content = f"""POST /upload HTTP/1.1
Host: api.example.com
X-Upload-Path: {upload_path_b64}
X-Client-Cert: {cert_b64}
Cookie: session_token={session_token}; other=123

data
"""
    with open(os.path.join(path, filename), "w") as f:
        f.write(content)

# Clean
for i in range(20):
    write_req("/app/corpora/clean", f"req_{i}.txt", trusted_cert_b64, f"images/pic_{i}.png", f"AUTH_user{i}")

# Evil
# 1. Path traversal
for i in range(7):
    write_req("/app/corpora/evil", f"req_path_{i}.txt", trusted_cert_b64, f"images/../private/pic_{i}.png", f"AUTH_user{i}")

# 2. Untrusted cert
for i in range(7):
    write_req("/app/corpora/evil", f"req_cert_{i}.txt", untrusted_cert_b64, f"images/pic_{i}.png", f"AUTH_user{i}")

# 3. Guest session
for i in range(6):
    write_req("/app/corpora/evil", f"req_session_{i}.txt", trusted_cert_b64, f"images/pic_{i}.png", f"GUEST_1234{i}")

EOF
    python3 /app/generate_corpus.py
    rm -f /app/generate_corpus.py /app/*.key /app/*.csr /app/*.crt /app/*.srl

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
