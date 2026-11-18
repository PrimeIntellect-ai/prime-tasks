#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip iputils-ping gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/traffic.log
[2023-10-27 14:32:01] INCOMING HTTP REQUEST
GET /api/diagnostics?token=admin_session&data=MTI3LjAuMC4xO2NhdCAvZXRjL2hvc3Rz HTTP/1.1
Host: internal-router.local
User-Agent: curl/7.68.0
Accept: */*
EOF

    cat << 'EOF' > /home/user/service.sh
#!/bin/bash
# Internal Diagnostic Service v1.0
if [ -z "$1" ]; then
    echo "Usage: $0 <base64_encoded_ip>"
    exit 1
fi

# Decode the input
decoded_ip=$(echo "$1" | base64 -d)

# Perform the diagnostic ping (VULNERABLE TO COMMAND INJECTION)
eval "ping -c 1 $decoded_ip" > /dev/null 2>&1
EOF

    chmod +x /home/user/service.sh
    chmod -R 777 /home/user
