#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install dependencies required by the script
    apt-get install -y openssl coreutils grep

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create the vulnerable verification script
    cat << 'EOF' > /home/user/verify_token.sh
#!/bin/bash
TOKEN_FILE=$1

if [ ! -f "$TOKEN_FILE" ]; then
    echo "Token file missing."
    exit 1
fi

TOKEN=$(cat "$TOKEN_FILE")
HEADER_B64=$(echo "$TOKEN" | cut -d'.' -f1)
PAYLOAD_B64=$(echo "$TOKEN" | cut -d'.' -f2)
SIGNATURE_B64=$(echo "$TOKEN" | cut -d'.' -f3)

HEADER=$(echo "$HEADER_B64" | base64 -d 2>/dev/null)
PAYLOAD=$(echo "$PAYLOAD_B64" | base64 -d 2>/dev/null)

# Vulnerability: accepts "none" algorithm and skips cert/signature validation
if echo "$HEADER" | grep -q '"alg":"none"'; then
    VALID=1
else
    # Dummy certificate chain validation
    if openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt dummy_cert.pem >/dev/null 2>&1; then
        # Dummy signature check
        VALID=1
    else
        VALID=0
    fi
fi

if [ "$VALID" -eq 1 ]; then
    ROLE=$(echo "$PAYLOAD" | grep -oP '"role":"\K[^"]+')
    if [ "$ROLE" == "admin" ]; then
        echo "Granted admin access."
        exit 0
    else
        echo "Access denied."
        exit 1
    fi
else
    echo "Invalid signature."
    exit 1
fi
EOF

    # Make the script executable
    chmod +x /home/user/verify_token.sh

    # Ensure correct permissions for the user's home directory
    chmod -R 777 /home/user
