#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar sed
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /app/vendored
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Set up JWT secret
    echo -n "super_secret_compliance_key_2023!" > /home/user/jwt_secret.key

    # Generate captured tokens
    pip3 install pyjwt==2.8.0
    python3 -c "
import jwt, time
secret = 'super_secret_compliance_key_2023!'
t1 = jwt.encode({'user_id': 'user_001', 'exp': int(time.time()) + 3600}, secret, algorithm='HS256')
t2 = jwt.encode({'user_id': 'user_002', 'exp': int(time.time()) - 3600}, secret, algorithm='HS256')
t3 = jwt.encode({'user_id': 'user_003', 'exp': int(time.time()) + 3600}, 'wrong_secret', algorithm='HS256')
with open('/home/user/captured_tokens.txt', 'w') as f:
    f.write(t1 + '\n' + t2 + '\n' + t3 + '\n')
"
    pip3 uninstall -y pyjwt

    # Vendored PyJWT
    cd /tmp
    wget https://github.com/jpadilla/pyjwt/archive/refs/tags/2.8.0.tar.gz
    tar -xzf 2.8.0.tar.gz
    mv pyjwt-2.8.0 /app/vendored/
    rm 2.8.0.tar.gz

    # Inject perturbation
    sed -i '/def decode(/a \        raise DecodeError("Task perturbation")' /app/vendored/pyjwt-2.8.0/jwt/api_jwt.py

    # Create corpora
    cat << 'EOF' > /app/corpora/evil/evil1.log
User logged in with AWS key AKIAIOSFODNN7EXAMPLE and CC 4111-2222-3333-4444.
Token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
EOF

    cat << 'EOF' > /app/corpora/clean/clean1.log
Git commit 3b18e512dba79e4c8300dd08aeb37f8e728b8dad deployed.
UUID 123e4567-e89b-12d3-a456-426614174000 processed successfully.
Transaction ID: TXN-9876543210ABCDEF
EOF

    # Permissions
    chmod -R 777 /app
    chmod -R 777 /home/user
