#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu
    pip3 install pytest

    mkdir -p /app
    mkdir -p /opt

    # Fix ImageMagick security policy to allow writing PNGs and reading fonts
    sed -i 's/rights="none" pattern="PNG"/rights="read | write" pattern="PNG"/' /etc/ImageMagick-6/policy.xml || true

    # Generate an image with the text
    convert -size 600x200 xc:black -font DejaVu-Sans-Mono -pointsize 24 -fill red -draw "text 20,100 'FATAL CRASH IN MODULE_ID: ALFA_TX_99'" /app/error_screenshot.png

    # Create a simulated memory dump with binary garbage and the config strings
    dd if=/dev/urandom of=/app/crash.dmp bs=1024 count=1024
    echo "CONFIG LOADED FOR ALFA_TX_99 -> VALID_RECORD_REGEX: [A-Z]{4}-[0-9]{4}:[0-9]{1,5}" >> /app/crash.dmp
    echo "CONFIG LOADED FOR BETA_TX_01 -> VALID_RECORD_REGEX: [0-9]{4}-[A-Z]{4}:[0-9]{1,5}" >> /app/crash.dmp
    dd if=/dev/urandom bs=1024 count=512 >> /app/crash.dmp
    chmod 644 /app/crash.dmp

    # Create oracle script
    cat << 'EOF' > /opt/oracle_wal_recover.sh
#!/bin/bash
# Oracle implementation to extract the specific format
grep -a -o -E '[A-Z]{4}-[0-9]{4}:[0-9]{1,5}'
EOF
    chmod +x /opt/oracle_wal_recover.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
