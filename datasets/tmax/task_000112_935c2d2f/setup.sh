#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install --default-timeout=100 pytest pytesseract Pillow

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate the image
    convert -background white -fill black -font DejaVu-Sans -pointsize 24 label:"SECURITY BASELINE REQUIREMENT:\n MaxAuthTries 3\n ClientAliveInterval 300\n PermitEmptyPasswords no" /app/policy_baseline.png

    # Clean corpus
    cat << 'EOF' > /app/corpus/clean/clean1.conf
MaxAuthTries 3
ClientAliveInterval 300
PermitEmptyPasswords no
Port 22
EOF

    cat << 'EOF' > /app/corpus/clean/clean2.conf
maxauthtries    3 
 clientaliveinterval 300
permitemptypasswords   no
EOF

    # Evil corpus
    cat << 'EOF' > /app/corpus/evil/evil1_injection.conf
MaxAuthTries 3
ClientAliveInterval 300
PermitEmptyPasswords no
# malicious comment ; rm -rf /
EOF

    cat << 'EOF' > /app/corpus/evil/evil2_policy.conf
MaxAuthTries 4
ClientAliveInterval 300
PermitEmptyPasswords no
EOF

    cat << 'EOF' > /app/corpus/evil/evil3_missing.conf
ClientAliveInterval 300
PermitEmptyPasswords no
EOF

    cat << 'EOF' > /app/corpus/evil/evil4_pipe.conf
MaxAuthTries 3
ClientAliveInterval 300
PermitEmptyPasswords no
Banner /etc/issue | wall
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
