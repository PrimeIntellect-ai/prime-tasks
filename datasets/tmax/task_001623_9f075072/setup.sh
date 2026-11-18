#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak jq coreutils
    pip3 install pytest PyJWT

    mkdir -p /app/corpora/clean /app/corpora/evil /home/user

    # Generate Audio
    espeak -w /app/incident_report.wav "The breach originated from IP address 198.51.100.45. The system uses the shared secret key 'BlueberrySky123' for its tokens."

    # Create vulnerable app
    cat << 'EOF' > /home/user/vulnerable_app.sh
#!/bin/bash
TOKEN=$1
HEADER=$(echo $TOKEN | cut -d. -f1 | base64 -d 2>/dev/null)
ALG=$(echo $HEADER | grep -o '"alg":"none"' || true)
if [ -n "$ALG" ]; then
  echo "Access Granted (Bypass)"
else
  echo "Checking signature..."
fi
EOF
    chmod +x /home/user/vulnerable_app.sh

    # Create checksum
    cd /home/user
    sha256sum vulnerable_app.sh > checksums.txt

    # Generate JWT corpora
    python3 -c "
import jwt
import os
import json
import base64

secret = 'BlueberrySky123'
wrong_secret = 'StrawberryEarth456'

clean_dir = '/app/corpora/clean/'
evil_dir = '/app/corpora/evil/'

# Clean tokens
for i in range(5):
    payload = {'user': f'user{i}', 'admin': False}
    token = jwt.encode(payload, secret, algorithm='HS256')
    with open(f'{clean_dir}/token_{i}.txt', 'w') as f:
        f.write(token)

# Evil tokens
payload = {'user': 'attacker', 'admin': True}

# 1. alg: none
header = base64.urlsafe_b64encode(b'{\"alg\":\"none\",\"typ\":\"JWT\"}').decode('utf-8').rstrip('=')
body = base64.urlsafe_b64encode(json.dumps(payload).encode('utf-8')).decode('utf-8').rstrip('=')
token_none = f'{header}.{body}.'
with open(f'{evil_dir}/token_none.txt', 'w') as f:
    f.write(token_none)

# 2. wrong secret
token_wrong = jwt.encode(payload, wrong_secret, algorithm='HS256')
with open(f'{evil_dir}/token_wrong.txt', 'w') as f:
    f.write(token_wrong)

# 3. modified payload but original signature
token_clean = jwt.encode({'user': 'attacker', 'admin': False}, secret, algorithm='HS256')
parts = token_clean.split('.')
parts[1] = body
token_tampered = f'{parts[0]}.{parts[1]}.{parts[2]}'
with open(f'{evil_dir}/token_tampered.txt', 'w') as f:
    f.write(token_tampered)
"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
