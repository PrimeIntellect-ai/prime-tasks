#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect logrotate procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_sensor_bin
#!/bin/bash
echo -n "Device Name? "
read dev_name
echo -n "Mode? "
read mode
echo "Initializing $dev_name in $mode mode..."
while true; do
    echo "$(date +%s) - $dev_name - $mode - Sensor reading: $RANDOM"
    sleep 0.5
done
EOF
    chmod +x /home/user/legacy_sensor_bin

    chmod -R 777 /home/user
