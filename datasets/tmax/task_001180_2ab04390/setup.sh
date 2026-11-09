#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip expect gcc git bash
pip3 install pytest

mkdir -p /home/user/tools /home/user/profiles

cat << 'EOF' > /home/user/tools/create_profile.sh
#!/bin/bash
read -p "Enter Username: " u
read -p "Enter Role: " r
read -p "Enter Status: " s
echo -e "Username: $u\nRole: $r\nStatus: $s" > /home/user/profiles/$u.txt
echo "Profile $u.txt created."
EOF
chmod +x /home/user/tools/create_profile.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
