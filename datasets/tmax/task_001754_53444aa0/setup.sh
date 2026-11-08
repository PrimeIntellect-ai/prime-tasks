#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak
pip3 install pytest

mkdir -p /app

# Generate the audio file
espeak -w /app/audit_rules.wav "Create a bash script at /home/user/validator.sh that takes exactly two arguments. The first argument is a base64 encoded web payload. Decode it. First, check the decoded payload. If the decoded string contains the exact substring '<script>' or 'javascript:' or 'onerror=', print 'REJECT_XSS' and exit. If it passes the XSS check, look at the second argument, which represents a file path. If the path does not start with exactly '/var/www/uploads/' or if the path contains the string '..', print 'REJECT_PATH' and exit. If both the payload and the path pass these checks, print 'ACCEPT'."

# Create oracle.sh
cat << 'EOF' > /app/oracle.sh
#!/bin/bash
decoded=$(echo "$1" | base64 -d 2>/dev/null)
if [[ "$decoded" == *"<script>"* ]] || [[ "$decoded" == *"javascript:"* ]] || [[ "$decoded" == *"onerror="* ]]; then
    echo "REJECT_XSS"
elif [[ "$2" != /var/www/uploads/* ]] || [[ "$2" == *".."* ]]; then
    echo "REJECT_PATH"
else
    echo "ACCEPT"
fi
EOF
chmod +x /app/oracle.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
