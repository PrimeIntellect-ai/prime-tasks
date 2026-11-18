#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    # Generate the intercepted VoIP audio
    espeak -w /app/intercepted_voip.wav "Initiate phase two of Operation Crimson Hawk immediately."

    # Create the Python script and compile it to .pyc
    cat << 'EOF' > /app/cert_validator.py
import re
ROGUE_CERT_CN = "badguy.exfil.net"
AUTH_TOKEN_REGEX = r"X-Auth-Token: [A-Za-z0-9]{32}"
def validate_tls(cert_cn):
    return cert_cn == ROGUE_CERT_CN
EOF
    python3 -c 'import py_compile; py_compile.compile("/app/cert_validator.py", cfile="/app/cert_validator.pyc")'
    rm /app/cert_validator.py

    # Populate the evil corpus
    cat << 'EOF' > /app/corpus/evil/log1.log
Connection to badguy.exfil.net established. X-Auth-Token: aB3dE6gH8jK1mN4pQ7sT9vW2xY5zA8cC. Subject discussed Operation Crimson hawk.
EOF
    cat << 'EOF' > /app/corpus/evil/log2.log
User authenticated. X-Auth-Token: 1234567890abcdef1234567890abcdef. No codename mentioned.
EOF

    # Populate the clean corpus
    cat << 'EOF' > /app/corpus/clean/log1.log
Connection to legitimate.net established. X-Auth-Token-Legacy: false. Subject discussed normal things.
EOF
    cat << 'EOF' > /app/corpus/clean/log2.log
No sensitive data here. Operation Blue Falcon was a success.
EOF

    # Create the user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
