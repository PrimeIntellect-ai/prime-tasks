#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip expect
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/legacy_app
mkdir -p /home/user/scripts

cat << 'EOF' > /home/user/legacy_app/cli_tool.sh
#!/bin/bash
read -p "Please enter diagnostic PIN: " pin
if [ "$pin" != "8472" ]; then
    echo "Invalid PIN."
    exit 1
fi

echo "Initializing diagnostics..."
sleep 0.5
echo "Memory: OK"
echo "CPU: OK"

# Read state from file or default to HEALTHY
state="HEALTHY"
if [ -f /home/user/legacy_app/internal_state.dat ]; then
    state=$(cat /home/user/legacy_app/internal_state.dat)
fi

echo "[STATE] $state"
echo "Diagnostics complete."
EOF
chmod +x /home/user/legacy_app/cli_tool.sh

echo "CRITICAL_ERROR" > /home/user/legacy_app/internal_state.dat

chmod -R 777 /home/user
