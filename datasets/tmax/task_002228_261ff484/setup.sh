#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip expect
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/launcher.sh
#!/bin/bash
# System services launcher

start_capacity_tool() {
    echo "Starting capacity tool..."
    # Fails if proxy is not up
}

start_proxy() {
    echo "Starting reverse proxy..."
}

# START ORDER
start_capacity_tool
start_proxy
EOF
chmod +x /home/user/launcher.sh

cat << 'EOF' > /home/user/capacity_cli
#!/bin/bash
read -p "Enter Target Timezone: " tz
read -p "Enter System Locale: " loc
read -p "Enter Planner Username: " usr
read -p "Enter Planner Group: " grp

echo "=== CAPACITY PROJECTION ==="
echo "TZ: $tz"
echo "LOC: $loc"
echo "USER: $usr"
echo "GROUP: $grp"
echo "STATUS: SUCCESS"
EOF
chmod +x /home/user/capacity_cli

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
