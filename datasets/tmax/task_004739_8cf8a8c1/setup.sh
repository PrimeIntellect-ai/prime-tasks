#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick zip unzip openssh-client
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create evidence image
    convert -size 400x100 xc:white -fill black -pointsize 24 -draw "text 10,50 'Decryption PIN: 773921'" /app/evidence.png

    # Create malware binary and zip
    echo "MZ... EXFIL_PATTERN: TRK-[A-Z0-9]{6}-[A-Z0-9]{6} ...EOF" > /tmp/exfil.bin
    zip -P 773921 -j /app/malware.zip /tmp/exfil.bin
    rm /tmp/exfil.bin

    # Populate corpus
    echo "Normal web log entry 1" > /app/corpus/clean/log1.txt
    echo "Normal web log entry 2" > /app/corpus/clean/log2.txt

    echo "Leaked credential: TRK-ABC123-XYZ987 in the logs" > /app/corpus/evil/log1.txt
    cat << 'EOF' > /app/corpus/evil/log2.txt
Some log data
-----BEGIN OPENSSH PRIVATE KEY-----
bHBlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
-----END OPENSSH PRIVATE KEY-----
More log data
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
