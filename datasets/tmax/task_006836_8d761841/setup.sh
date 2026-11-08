#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Run this setup script to prepare the environment before the agent starts
    mkdir -p /home/user/uploads
    mkdir -p /home/user/quarantine

    # Create good files and compute hashes
    echo "valid data 1" > /home/user/uploads/file1.txt
    echo "valid data 2" > /home/user/uploads/file2.txt
    sha256sum /home/user/uploads/file1.txt /home/user/uploads/file2.txt | sed 's|/home/user/uploads/||' > /home/user/hashes.txt

    # Create compromised/unauthorized files
    echo "tampered data" > /home/user/uploads/file3.txt
    echo "malware payload" > /home/user/uploads/bad_actor.sh

    # Create vulnerable script
    cat << 'EOF' > /home/user/upload_handler.sh
#!/bin/bash
FILENAME=$1
SOURCE_FILE=$2

# Vulnerable copy
cp "$SOURCE_FILE" "/home/user/uploads/$FILENAME"
echo "Uploaded successfully"
EOF
    chmod +x /home/user/upload_handler.sh

    # Create initial network rules
    echo "ALLOW 10.0.0.0/8" > /home/user/network_rules.conf
    echo "DENY 203.0.113.5" >> /home/user/network_rules.conf

    # Create old tokens file
    echo "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef  -" > /home/user/valid_tokens.txt

    chmod -R 777 /home/user
