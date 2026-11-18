#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip xxd
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.sh
#!/bin/bash
mkdir -p /home/user/raw_project/assets
mkdir -p /home/user/organized

# Create the config file
cat << 'CONFEOF' > /home/user/raw_project/organize.conf
89504e47:images/png
7f454c46:binaries/elf
ffd8ffe0:images/jpeg
CONFEOF

# Create asset files
printf "\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x01" > /home/user/raw_project/assets/asset_A
printf "\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00" > /home/user/raw_project/assets/asset_B
printf "\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x01" > /home/user/raw_project/assets/asset_C
printf "\x11\x22\x33\x44\x55\x66\x77" > /home/user/raw_project/assets/asset_D
printf "\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x01" > /home/user/raw_project/assets/asset_E
printf "\xff\xd8\xff\xe0\x00\x10\x4a\x46\x49\x46\x00\x01" > /home/user/raw_project/assets/asset_F
printf "\x11\x22\x33\x44\x55\x66\x77" > /home/user/raw_project/assets/asset_G
EOF

bash /tmp/setup.sh
rm /tmp/setup.sh

chown -R user:user /home/user/raw_project
chmod -R 777 /home/user
