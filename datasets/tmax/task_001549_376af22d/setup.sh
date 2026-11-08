#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create the /app directory and the dummy legacy_detector executable
    mkdir -p /app
    cat << 'EOF' > /app/legacy_detector
#!/bin/bash
# Dummy legacy detector for initial state tests
echo "ts,metric,mean,std,anomaly,clean_msg"
EOF
    chmod +x /app/legacy_detector

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
