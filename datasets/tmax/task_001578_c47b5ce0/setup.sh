#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pexpect

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_logs

    cat << 'EOF' > /home/user/legacy_service.sh
#!/bin/bash
read -p "Enter monitor password: " PASS
if [ "$PASS" = "alertadmin" ]; then
    echo "STATUS: FAILURE_DETECTED"
else
    echo "STATUS: UNAUTHORIZED"
fi
EOF
    chmod +x /home/user/legacy_service.sh

    chmod -R 777 /home/user
