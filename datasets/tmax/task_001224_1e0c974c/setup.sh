#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ coreutils
pip3 install pytest

mkdir -p /home/user/project_data/src
mkdir -p /home/user/project_data/assets

echo "int main() { return 0; }" > /home/user/project_data/src/main.cpp
echo "config=1" > /home/user/project_data/config.txt
echo "binary data" > /home/user/project_data/assets/logo.png

cat << 'EOF' > /home/user/manifest_v1.csv
assets/old_file.txt,e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
config.txt,b4a458eb23ce0eb7ebbc776602bb4d0bf9423c72e29e924dcfdaef013db2d416
src/main.cpp,dummy_old_hash_to_force_update
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
