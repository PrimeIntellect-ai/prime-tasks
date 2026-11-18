#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install ImageMagick, fonts, and Tesseract OCR for the agent
    apt-get install -y imagemagick fonts-dejavu-core tesseract-ocr

    # Create /app directory
    mkdir -p /app

    # Generate the policy memo image
    echo "SECURITY DIRECTIVE: CRITICAL_CWE=CWE-78\nTRUSTED_HASH=88d4266fd4e6338d13b845fcf289579d209c897823b9217da3e161936f031589" > /tmp/memo.txt
    # ImageMagick 6 security policy might block label:@, so we use convert directly or update policy
    sed -i 's/rights="none" pattern="LABEL"/rights="read|write" pattern="LABEL"/' /etc/ImageMagick-6/policy.xml || true
    sed -i 's/rights="none" pattern="@\*"/rights="read|write" pattern="@\*"/' /etc/ImageMagick-6/policy.xml || true
    convert -background white -fill black -font DejaVu-Sans -pointsize 18 label:@/tmp/memo.txt /app/policy_memo.png

    # Create the oracle script
    cat << 'EOF' > /app/oracle.sh
#!/bin/bash
CRITICAL_CWE="CWE-78"
TRUSTED_HASH="88d4266fd4e6338d13b845fcf289579d209c897823b9217da3e161936f031589"

while IFS='|' read -r filepath filehash cwe message || [ -n "$filepath" ]; do
    if [ "$cwe" = "CWE-000" ]; then
        echo "CONFIG_ERROR|$filepath"
    elif [ "$filehash" != "$TRUSTED_HASH" ]; then
        echo "INTEGRITY_VIOLATION|$filepath"
    elif [ "$cwe" = "$CRITICAL_CWE" ]; then
        echo "CWE_ALERT|$filepath|$message"
    else
        echo "COMPLIANT|$filepath"
    fi
done
EOF
    chmod +x /app/oracle.sh

    # Create user and home directory
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
