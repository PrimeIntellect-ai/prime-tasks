#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/
    cat << 'EOF' > /home/user/dropper_build.sh
#!/bin/bash
echo "Starting dropper build sequence..."

# Simulate configuration generation
SLEEP_TIME=$(( RANDOM % 3 ))
sleep $SLEEP_TIME

# Buggy calculation causing intermittent failure (division by zero when RANDOM % 5 == 0)
PAYLOAD_SIZE=$(( 10000 / (RANDOM % 5) ))

echo "Payload size calculated: $PAYLOAD_SIZE"
echo "Generating stub..."
# Simulate successful build
exit 0
EOF
    chmod +x /home/user/dropper_build.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
