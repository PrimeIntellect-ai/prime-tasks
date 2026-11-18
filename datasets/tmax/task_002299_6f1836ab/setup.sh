#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Setup directories
mkdir -p /app/corpus/clean /app/corpus/evil /app/bats-core/bin /home/user

# Create clean corpus
echo "INFO: Authentication flow started for user admin" > /app/corpus/clean/log1.txt
echo "DEBUG: Port 22 is open, SSH service running" > /app/corpus/clean/log2.txt
echo "GET /api/status HTTP/1.1 200 OK" > /app/corpus/clean/log3.txt
echo "AKIB1234567890ABCDEF is not an access key" > /app/corpus/clean/log4.txt
echo "Authorization: Basic dXNlcjpwYXNz" > /app/corpus/clean/log5.txt

# Create evil corpus
echo "Error parsing key: -----BEGIN RSA PRIVATE KEY-----" > /app/corpus/evil/log1.txt
echo "Found credentials: AKIA1234567890ABCDEF in env" > /app/corpus/evil/log2.txt
echo "GET /api/data?token=Bearer%20eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9 HTTP/1.1" > /app/corpus/evil/log3.txt
echo "Authorization: Bearer abcdef1234567890_.-XYZ" > /app/corpus/evil/log4.txt
echo "Saved key to id_ed25519: -----BEGIN OPENSSH PRIVATE KEY-----" > /app/corpus/evil/log5.txt

# Create broken bats-core executable fixture
cat << 'EOF' > /app/bats-core/bin/bats
#!/bin/broken-bash
echo "Bats 1.9.0"
exit 0
EOF
chmod +x /app/bats-core/bin/bats

# Create user
useradd -m -s /bin/bash user || true

# Set ownership and permissions
chown -R user:user /app /home/user
chmod -R 777 /app
chmod -R 777 /home/user
