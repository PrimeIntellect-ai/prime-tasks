#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the dummy ELF binary with the secret
    cat << 'EOF' > /tmp/legacy_worker.c
#include <stdio.h>
int main() {
    const char *secret = "COMPLIANCE_KEY_ab89c7f4d2";
    printf("Worker starting...\n");
    return 0;
}
EOF
    gcc /tmp/legacy_worker.c -o /home/user/legacy_worker
    rm /tmp/legacy_worker.c

    # Generate raw_audit.log with Python
    python3 -c '
import hmac, hashlib, base64
header_payload = b"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoiYWRtaW4ifQ"
secret = b"COMPLIANCE_KEY_ab89c7f4d2"
sig = base64.urlsafe_b64encode(hmac.new(secret, header_payload, hashlib.sha256).digest()).decode("utf-8").rstrip("=")
valid_token = f"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoiYWRtaW4ifQ.{sig}"

log_content = f"""2023-10-01 10:00:01 /usr/bin/python3 app.py --port 8080
2023-10-01 10:05:12 /home/user/legacy_worker --task sync --token {valid_token} --verbose
2023-10-01 10:06:00 /home/user/legacy_worker --task backup --token eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoiYWRtaW4ifQ.invalid_sig_here --force
2023-10-01 10:10:05 /bin/bash script.sh --token invalid_token_format
"""
with open("/home/user/raw_audit.log", "w") as f:
    f.write(log_content)
'

    chmod -R 777 /home/user
