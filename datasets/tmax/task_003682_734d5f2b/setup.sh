#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar
    pip3 install pytest PyJWT==2.4.0

    # Setup vendored pyjwt
    mkdir -p /app
    cd /app
    wget https://github.com/jpadilla/pyjwt/archive/refs/tags/2.4.0.tar.gz
    tar -xzf 2.4.0.tar.gz
    mv pyjwt-2.4.0 pyjwt
    rm 2.4.0.tar.gz

    # Inject perturbation
    sed -i '/def _verify_signature(/a \        if header.get("alg") == "none": return True' /app/pyjwt/jwt/api_jws.py

    # Setup corpora
    mkdir -p /home/user/corpora/evil
    mkdir -p /home/user/corpora/clean

    cat << 'EOF' > /tmp/gen_tokens.py
import jwt
import base64

SECRET = "vulnerability-scan-2024"

# Generate Clean Tokens
for i in range(50):
    payload = {
        "csp_directive": "default-src 'self'",
        "b64_payload": base64.b64encode(f"safe data {i}".encode()).decode()
    }
    token = jwt.encode(payload, SECRET, algorithm="HS256")
    with open(f"/home/user/corpora/clean/token_{i}.txt", "w") as f:
        f.write(token)

# Generate Evil Tokens
for i in range(50):
    if i < 15:
        # alg=none
        payload = {"csp_directive": "default-src 'self'", "b64_payload": base64.b64encode(b"safe").decode()}
        token = jwt.encode(payload, "", algorithm="none")
    elif i < 30:
        # unsafe-inline
        payload = {"csp_directive": "default-src 'self' 'unsafe-inline'", "b64_payload": base64.b64encode(b"safe").decode()}
        token = jwt.encode(payload, SECRET, algorithm="HS256")
    else:
        # script tag
        payload = {"csp_directive": "default-src 'self'", "b64_payload": base64.b64encode(b"<script>alert(1)</script>").decode()}
        token = jwt.encode(payload, SECRET, algorithm="HS256")

    with open(f"/home/user/corpora/evil/token_{i}.txt", "w") as f:
        f.write(token)
EOF
    python3 /tmp/gen_tokens.py
    rm /tmp/gen_tokens.py

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
