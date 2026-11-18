#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect
    pip3 install pytest

    mkdir -p /home/user/bin
    mkdir -p /home/user/dashboard

    cat << 'EOF' > /home/user/bin/telemetry-cli
#!/bin/bash

if [ "$TZ" != "UTC" ]; then
    echo "Error: TZ must be UTC"
    exit 1
fi

if [ "$LC_ALL" != "en_US.UTF-8" ]; then
    echo "Error: LC_ALL must be en_US.UTF-8"
    exit 1
fi

if [ "$METRICS_DASHBOARD_URL" != "http://localhost:9090/api/push" ]; then
    echo "Error: METRICS_DASHBOARD_URL is incorrect"
    exit 1
fi

echo -n "Enter telemetry password: "
read -s password
echo

if [ "$password" != "obsv-dash-2024" ]; then
    echo "Authentication failed."
    exit 1
fi

echo "Authentication successful."
echo "Dashboard feed active. Pushing to $METRICS_DASHBOARD_URL"
while true; do
    sleep 5
    echo "Pushed 10 metrics..."
done
EOF

    chmod +x /home/user/bin/telemetry-cli

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
