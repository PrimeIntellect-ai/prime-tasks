#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/configs
mkdir -p /home/user/binaries

# Use python to safely write exact bytes
python3 -c "
with open('/home/user/binaries/a.bin', 'wb') as f:
    f.write(b'\x00'*8 + b'\x1A\x2B\x3C\x4D' + b'\x00'*8)
with open('/home/user/binaries/d.bin', 'wb') as f:
    f.write(b'\x00'*8 + b'\xF5\xE6\xD7\xC8' + b'\x00'*8)
"

echo "BinPath=/home/user/binaries/a.bin" > /home/user/configs/main.ini
echo "BinPath=/home/user/binaries/d.bin" > /home/user/configs/backup.ini

ln -s /home/user/configs/main.ini /home/user/configs/link_to_main.ini
ln -s /home/user/configs/loop2.ini /home/user/configs/loop1.ini
ln -s /home/user/configs/loop1.ini /home/user/configs/loop2.ini

chmod -R 777 /home/user
