#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg fonts-dejavu-core openssl
    pip3 install pytest

    mkdir -p /app

    # Create the oracle script
    cat << 'EOF' > /app/oracle_enforce_policy.sh
#!/bin/bash
INPUT="$1"
if [[ "$INPUT" == *"redirect_uri=http://"* ]] || [[ "$INPUT" == *"redirect_uri=https://"* ]]; then
    echo "CWE-601"
elif [[ "$INPUT" == *"<script>"* ]] || [[ "$INPUT" == *"javascript:"* ]]; then
    echo "CWE-79"
elif [[ "$INPUT" == *"X-Admin-Access: true"* ]] && [[ "$INPUT" == *"Cookie: bypass="* ]]; then
    echo "AUTH_BYPASS"
else
    echo "SAFE"
fi
EOF
    chmod +x /app/oracle_enforce_policy.sh

    # Create the encrypted policy file
    cat << 'EOF' > /tmp/policy_raw.txt
Log Auditing Policy Specification:
1. Check for CWE-601 (Open Redirect): match substrings 'redirect_uri=http://' or 'redirect_uri=https://'.
2. Check for CWE-79 (XSS): match substrings '<script>' or 'javascript:'.
3. Check for AUTH_BYPASS: requires both 'X-Admin-Access: true' and 'Cookie: bypass='.
4. Fallback: SAFE.
Match order is strictly 1 -> 2 -> 3.
EOF
    openssl enc -aes-256-cbc -pbkdf2 -in /tmp/policy_raw.txt -out /app/policy_def.enc -pass pass:DevSecOps_attack

    # Generate the incident record video
    echo "curl -v 'https://api.internal/login?redirect_uri=attackersite.com/login'" > /tmp/video_text.txt
    ffmpeg -f lavfi -i color=c=black:s=800x600:d=6 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:textfile=/tmp/video_text.txt:fontcolor=white:fontsize=24:x=50:y=300:enable='between(t,3,5)'" -c:v libx264 /app/incident_record.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
