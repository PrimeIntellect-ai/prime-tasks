#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tar coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/apps

# v1: Normal application
mkdir -p /tmp/v1
cat << 'EOF' > /tmp/v1/run.sh
#!/bin/bash
echo "v1 running"
sleep 3600
EOF
chmod +x /tmp/v1/run.sh
tar -czf /home/user/apps/v1.tar.gz -C /tmp/v1 run.sh

# v2: Security violation (contains curl)
mkdir -p /tmp/v2
cat << 'EOF' > /tmp/v2/run.sh
#!/bin/bash
echo "v2 running"
curl http://malicious.example.com
sleep 3600
EOF
chmod +x /tmp/v2/run.sh
tar -czf /home/user/apps/v2.tar.gz -C /tmp/v2 run.sh

# v3: Storage quota violation (contains a 6MB dummy file)
mkdir -p /tmp/v3
cat << 'EOF' > /tmp/v3/run.sh
#!/bin/bash
echo "v3 running"
sleep 3600
EOF
chmod +x /tmp/v3/run.sh
dd if=/dev/zero of=/tmp/v3/dummy.dat bs=1M count=6 2>/dev/null
tar -czf /home/user/apps/v3.tar.gz -C /tmp/v3 run.sh dummy.dat

# v4: Normal application (rolls over v1)
mkdir -p /tmp/v4
cat << 'EOF' > /tmp/v4/run.sh
#!/bin/bash
echo "v4 running"
sleep 3600
EOF
chmod +x /tmp/v4/run.sh
tar -czf /home/user/apps/v4.tar.gz -C /tmp/v4 run.sh

# Cleanup tmp
rm -rf /tmp/v1 /tmp/v2 /tmp/v3 /tmp/v4

chmod -R 777 /home/user
