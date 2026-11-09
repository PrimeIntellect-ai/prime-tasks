#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create task directories and files
    mkdir -p /home/user/mail_spool

    cat << 'EOF' > /home/user/worker.sh
#!/bin/bash
# Flaky worker simulation
sleep 0.5
exit 42
EOF
    chmod +x /home/user/worker.sh

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
