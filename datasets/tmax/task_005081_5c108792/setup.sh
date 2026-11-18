#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/custom_bin

    cat << 'EOF' > /home/user/custom_bin/mock_curl
#!/bin/bash
if [ "$1" == "http://auth.local/health" ]; then echo "500";
elif [ "$1" == "http://db.local/ping" ]; then echo "200";
elif [ "$1" == "http://cache.local/status" ]; then echo "200";
else echo "404";
fi
EOF
    chmod +x /home/user/custom_bin/mock_curl

    cat << 'EOF' > /home/user/services.conf
# Infrastructure Services Map
# Format: Name Endpoint ExpectedCode

AuthService http://auth.local/health 200

Database http://db.local/ping 200

Cache http://cache.local/status 200
UnknownService http://void.local/ping 200
EOF

    cat << 'EOF' > /home/user/monitor.sh
#!/bin/bash
# TODO: Ensure environment is loaded

cat /home/user/services.conf | while read name endpoint expected; do
    actual=$(mock_curl $endpoint)
    # Output logic broken, missing env vars
    echo "$name | $actual | $expected | UNKNOWN" >> $MONITOR_LOG_DIR/temp.log
done
EOF
    chmod +x /home/user/monitor.sh

    chmod -R 777 /home/user
