#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl coreutils grep gawk
pip3 install pytest

mkdir -p /home/user
cd /home/user

# Create the wordlist
cat << 'EOF' > /home/user/wordlist.txt
admin123
password
qwerty
letmein1
spring2024
autumn2023
winter2022
summer2021
hunter2
supersecret
EOF

# Create the staging token (secret: spring2024)
HDR="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
PAY="eyJ1c2VyIjoiZ3Vlc3QifQ"
SIG=$(echo -n "${HDR}.${PAY}" | openssl dgst -sha256 -hmac "spring2024" -binary | base64 | tr -d '=' | tr '+/' '-_')
echo -n "${HDR}.${PAY}.${SIG}" > /home/user/staging_token.jwt

# Create the vulnerable production gateway script
cat << 'EOF' > /home/user/prod_gateway.sh
#!/bin/bash
TOKEN=$1
if [ -z "$TOKEN" ]; then echo "Usage: $0 <token>"; exit 1; fi

# Function to decode base64url
decode_b64() {
    local len=$((${#1} % 4))
    local padded="$1"
    if [ $len -eq 2 ]; then padded="$padded=="; elif [ $len -eq 3 ]; then padded="$padded="; fi
    echo "$padded" | tr '\-_' '+/' | base64 -d 2>/dev/null
}

IFS='.' read -r header payload sig <<< "$TOKEN"
dec_hdr=$(decode_b64 "$header")
dec_pay=$(decode_b64 "$payload")

# CWE-347/CWE-287: Improper Verification of Cryptographic Signature (alg=none)
alg=$(echo "$dec_hdr" | grep -o '"alg"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 | tr '[:upper:]' '[:lower:]')

if [ "$alg" = "none" ]; then
    if [ -z "$sig" ]; then
        user=$(echo "$dec_pay" | grep -o '"user"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
        echo "Access Granted: $user"
        exit 0
    fi
    echo "Signature must be empty for none alg"
    exit 1
fi

# Strong verification for other algorithms
EXPECTED_SIG=$(echo -n "${header}.${payload}" | openssl dgst -sha256 -hmac "8f4e2d1c9b7a5f3e8d4c1b9a7f5e3d2c1b9a7f5e3d2c1b9a7f5e3d2c1b9a7f5e" -binary | base64 | tr -d '=' | tr '+/' '-_')

if [ "$sig" = "$EXPECTED_SIG" ]; then
    user=$(echo "$dec_pay" | grep -o '"user"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    echo "Access Granted: $user"
    exit 0
else
    echo "Access Denied: Invalid Signature"
    exit 1
fi
EOF

chmod +x /home/user/prod_gateway.sh

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
