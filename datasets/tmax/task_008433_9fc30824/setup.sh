#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/login_simulator.sh
#!/bin/bash
if [ "$AUTH_TOKEN" == "sysadmin_secret_991" ]; then
    echo "ACCESS_GRANTED" > /home/user/auth_result.log
else
    echo "ACCESS_DENIED: $AUTH_TOKEN" > /home/user/auth_result.log
fi
EOF
    chmod +x /home/user/login_simulator.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
