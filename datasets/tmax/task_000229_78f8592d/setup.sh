#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl procps gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user
    # 1. Create TLS cert and key
    openssl req -x509 -newkey rsa:2048 -keyout server.key -out server.crt -days 365 -nodes -subj "/CN=legacy-internal" 2>/dev/null

    # 2. Token plaintext and secret key
    PT="ACCESS_GRANTED_8839201_SYSTEM"
    KEY="Tr0ub4dour&3"

    # 3. XOR encryption
    python3 -c '
import sys
pt = sys.argv[1].encode()
key = sys.argv[2].encode()
out = bytearray()
for i in range(len(pt)):
    out.append(pt[i] ^ key[i % len(key)])
print(out.hex(), end="")
' "$PT" "$KEY" > token.enc

    # 4. Sign token.enc
    openssl dgst -sha256 -sign server.key -out token.sig token.enc

    # 5. Create legacy_auth.sh script
    cat << 'EOF' > /usr/local/bin/legacy_auth.sh
#!/bin/bash
sleep 1000000
EOF
    chmod +x /usr/local/bin/legacy_auth.sh

    # 6. Generate the expected hash for file integrity validation
    echo -n "$PT" | sha256sum | awk '{print $1}' > expected_hash.txt

    # 7. Cleanup private key and ensure correct ownership
    rm server.key
    chown -R user:user /home/user
    chmod -R 777 /home/user
