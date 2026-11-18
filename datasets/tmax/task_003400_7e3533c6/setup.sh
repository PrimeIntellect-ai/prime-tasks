#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/audit/logs
mkdir -p /home/user/audit/scripts
chmod -R 777 /home/user

echo "Log entry 1" > /home/user/audit/logs/log1.txt
echo "Log entry 2" > /home/user/audit/logs/log2.txt
echo "Log entry 3" > /home/user/audit/logs/log3.txt

cd /home/user/audit/logs
sha256sum log1.txt log2.txt log3.txt > /home/user/audit/checksums.sha256

echo "Tampered entry 2" > /home/user/audit/logs/log2.txt
echo "Tampered entry 3" > /home/user/audit/logs/log3.txt

echo "#!/bin/bash" > /home/user/audit/scripts/safe.sh
echo "echo 'Safe script running...'" >> /home/user/audit/scripts/safe.sh
chmod 755 /home/user/audit/scripts/safe.sh

echo "#!/bin/bash" > /home/user/audit/scripts/vuln.sh
echo "echo 'Processing data...'" >> /home/user/audit/scripts/vuln.sh
chmod 777 /home/user/audit/scripts/vuln.sh
