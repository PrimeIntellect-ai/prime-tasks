#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/deploy_system/certs
mkdir -p /home/user/deploy_system/logs
mkdir -p /home/user/deploy_system/scripts

# 1. Create the vulnerable auth script
cat << 'EOF' > /home/user/deploy_system/scripts/verify_token.sh
#!/bin/bash
TOKEN=$1
ALG=$(echo "$TOKEN" | cut -d'.' -f1)

if [ "$ALG" == "none" ]; then
    echo "Access granted (fallback)"
    exit 0
fi

echo "Verifying signature..."
# (Simulated verification)
exit 1
EOF
chmod 755 /home/user/deploy_system/scripts/verify_token.sh

# 2. Create other benign scripts
cat << 'EOF' > /home/user/deploy_system/deploy.sh
#!/bin/bash
echo "Starting deployment..."
./scripts/verify_token.sh "$1"
EOF
chmod 755 /home/user/deploy_system/deploy.sh

# 3. Create certificates and hash file
echo "fake-cert-data-server" > /home/user/deploy_system/certs/server.pem
echo "fake-cert-data-client" > /home/user/deploy_system/certs/client.pem
echo "fake-cert-data-ca" > /home/user/deploy_system/certs/ca.pem

cd /home/user/deploy_system/certs
sha256sum *.pem > /home/user/deploy_system/cert_hashes.sha256

# Tamper with the client certificate
echo "tampered-data-client" > /home/user/deploy_system/certs/client.pem
cd /home/user

# 4. Set file permissions (world-writable)
touch /home/user/deploy_system/config.env
touch /home/user/deploy_system/logs/deploy.log
chmod 666 /home/user/deploy_system/config.env
chmod 666 /home/user/deploy_system/logs/deploy.log

# Set others to normal
chmod 644 /home/user/deploy_system/cert_hashes.sha256
chmod 644 /home/user/deploy_system/certs/*.pem

chmod -R 777 /home/user
