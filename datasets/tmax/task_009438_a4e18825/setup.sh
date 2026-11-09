#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl ncat procps
pip3 install pytest

mkdir -p /home/user/uploads

# Generate certificates
openssl req -x509 -newkey rsa:2048 -keyout /ca.key -out /home/user/ca.pem -days 365 -nodes -subj "/CN=RootCA"
openssl req -newkey rsa:2048 -keyout /server.key -out /server.csr -nodes -subj "/CN=secure-upload.local"
openssl x509 -req -in /server.csr -CA /home/user/ca.pem -CAkey /ca.key -CAcreateserial -out /server.crt -days 365

# Create upload handler
cat << 'EOF' > /home/user/upload_handler.sh
#!/bin/bash
# Handles file upload metadata
read -r line
FILENAME=$(echo "$line" | cut -d' ' -f2)

# VULNERABILITY: Path Traversal (CWE-22)
TARGET_PATH="/home/user/uploads/$FILENAME"
echo "Saving to $TARGET_PATH"
EOF

chmod +x /home/user/upload_handler.sh

# Ensure service starts when a shell is opened
echo "pgrep ncat > /dev/null || ncat --ssl --ssl-cert /server.crt --ssl-key /server.key -l 8007 -k -c /home/user/upload_handler.sh &" >> /etc/bash.bashrc
echo "pgrep ncat > /dev/null || ncat --ssl --ssl-cert /server.crt --ssl-key /server.key -l 8007 -k -c /home/user/upload_handler.sh &" >> /root/.bashrc

useradd -m -s /bin/bash user || true
echo "pgrep ncat > /dev/null || ncat --ssl --ssl-cert /server.crt --ssl-key /server.key -l 8007 -k -c /home/user/upload_handler.sh &" >> /home/user/.bashrc

chmod -R 777 /home/user
