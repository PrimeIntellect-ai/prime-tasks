#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip expect cargo
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data_archive
dd if=/dev/zero of=/home/user/data_archive/dummy_data.bin bs=1048576 count=142

cat << 'EOF' > /home/user/billing_portal.sh
#!/bin/bash
# Force TTY check
if ! [ -t 0 ]; then
    echo "Error: Interactive TTY session required. Key-based or piped inputs rejected."
    exit 1
fi

# Read directly from TTY
read -s -p "Password: " pw < /dev/tty
echo ""

if [ "$pw" = "finops_secure" ]; then
    echo "Authentication successful."
    echo "STORAGE_RATE_PER_MB=0.035"
else
    echo "Authentication failed."
    exit 1
fi
EOF
chmod +x /home/user/billing_portal.sh

chmod -R 777 /home/user
