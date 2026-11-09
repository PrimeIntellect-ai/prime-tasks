#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick gcc
    pip3 install pytest

    mkdir -p /app/corpus
    mkdir -p /app/hidden_tests/clean
    mkdir -p /app/hidden_tests/evil

    # Generate backup_policy.png
    convert -background white -fill black -pointsize 18 label:"BACKUP POLICY RULES:\n1. The path must strictly begin with the prefix: /archive/trusted/\n2. The total length of the path must not exceed 256 characters.\n3. The file extension must be exactly .bak or .tar.gz\n4. Directory traversal sequences (..) are strictly forbidden anywhere in the path.\n5. The filename itself (everything after the last slash and before the valid extension) must consist EXCLUSIVELY of alphanumeric characters (A-Z, a-z, 0-9) and underscores (_). No spaces, hyphens, or special symbols." /app/backup_policy.png

    # Create corpus files
    cat << 'EOF' > /app/corpus/clean.txt
/archive/trusted/backup_2023.bak
/archive/trusted/user_data_01.tar.gz
/archive/trusted/system_config_FINAL.bak
EOF

    cat << 'EOF' > /app/corpus/evil.txt
/archive/trusted/../../etc/passwd.bak
/archive/trusted/backup-2023.bak
/backup/trusted/valid.bak
/archive/trusted/valid.zip
/archive/trusted/file;rm-rf/.tar.gz
/archive/trusted/spaced name.bak
EOF

    # Create hidden test files
    cp /app/corpus/clean.txt /app/hidden_tests/clean/clean.txt
    cp /app/corpus/evil.txt /app/hidden_tests/evil/evil.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
