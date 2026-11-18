#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget curl build-essential openssl
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/evidence
    mkdir -p /app/vendored

    # Generate fake implant binary
    cd /home/user/evidence
    cat << 'EOF' > implant.c
int main() {
    return 0;
}
EOF
    gcc implant.c -o implant.bin
    rm implant.c

    # Generate cert and key and append to binary
    openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes -subj "/CN=127.0.0.1"
    cat cert.pem >> implant.bin
    cat key.pem >> implant.bin
    echo "JWT_SECRET:s3cr3t_f0r_m4lw4r3_9912" >> implant.bin
    echo "C2_PAYLOAD:EXEC_SHELL_9921" >> implant.bin
    rm cert.pem key.pem

    # Setup vendored pyjwt
    cd /app/vendored
    wget https://github.com/jpadilla/pyjwt/archive/refs/tags/2.8.0.tar.gz
    tar -xzf 2.8.0.tar.gz
    rm 2.8.0.tar.gz

    # Sabotage the pyjwt library
    # Insert an unconditional raise inside _verify_signature
    sed -i '/def _verify_signature/a \        raise InvalidSignatureError("Signature verification failed")' pyjwt-2.8.0/jwt/api_jws.py

    # Create user
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user
