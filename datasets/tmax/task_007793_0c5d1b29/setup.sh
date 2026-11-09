#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/payload.txt
#!/bin/bash
TARGET_IP="192.168.1.100"
EXFIL_SERVER="http://malicious.com/drop"
echo "Dumping to $EXFIL_SERVER from $TARGET_IP"
/opt/tools/CREDENTIAL_DUMP
EOF

    chmod -R 777 /home/user
