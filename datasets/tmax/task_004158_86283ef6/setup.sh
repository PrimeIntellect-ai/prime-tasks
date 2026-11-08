#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick gcc tar gzip coreutils bash
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/evil /app/corpus/clean
    mkdir -p /home/user/backend/data /home/user/backend/logs
    mkdir -p /home/user/scripts

    # Create the architecture image with text
    convert -size 800x200 xc:white -pointsize 20 -fill black -draw "text 10,50 'System Architecture'" -draw "text 10,100 'SECRET_BACKUP_LOCATION=/home/user/archives/secure_backups'" /app/architecture.png

    # Create dummy data
    echo "dummy data 1" > /home/user/backend/data/data1.txt
    echo "dummy data 2" > /home/user/backend/data/data2.txt

    # Create corpus files
    # Evil corpus
    echo "SELECT * FROM users; DROP_TABLE users;" > /app/corpus/evil/payload1.txt
    printf "Valid text with \x0B hidden control char" > /app/corpus/evil/payload2.txt
    printf "Null byte \x00 here" > /app/corpus/evil/payload3.txt

    # Clean corpus
    echo "Just a normal payload with no weird characters." > /app/corpus/clean/payload1.txt
    echo '{"key": "value", "status": "ok"}' > /app/corpus/clean/payload2.txt
    echo "Another clean file with standard whitespace \n \t \r" > /app/corpus/clean/payload3.txt

    # Create the backup script
    cat << 'EOF' > /home/user/scripts/backup.sh
#!/bin/bash
# TODO: Fix this script
EOF
    chmod +x /home/user/scripts/backup.sh

    # Create the user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
