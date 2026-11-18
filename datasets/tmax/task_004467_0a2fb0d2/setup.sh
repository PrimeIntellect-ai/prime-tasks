#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_backend
#!/bin/bash
# Mock legacy backend
INPUT="$1"
if [[ "$INPUT" == EXEC* ]]; then
    PAYLOAD="${INPUT#EXEC }"
    echo "SUCCESS: $PAYLOAD"
else
    echo "FATAL: UNKNOWN"
fi
EOF
    chmod +x /home/user/legacy_backend

    chmod -R 777 /home/user
