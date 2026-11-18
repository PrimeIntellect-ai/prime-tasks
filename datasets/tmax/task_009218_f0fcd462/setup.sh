#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip zip
pip3 install pytest

mkdir -p /home/user/incoming /home/user/configs
echo '{"version": "1.0", "setting": "A"}' > /home/user/configs/app1.json
echo '{"version": "1.2", "setting": "B"}' > /home/user/configs/app2.json

mkdir -p /tmp/build
cd /tmp/build
echo '{"version": "1.1", "setting": "A_mod"}' > app1.json
echo '{"version": "2.0", "setting": "C"}' > app3.json
echo 'echo pwned' > evil.sh
ln -s /etc/passwd badlink

cat << 'EOF' > /tmp/build_tar.py
import tarfile
with tarfile.open('/tmp/payload.tar', 'w') as tar:
    tar.add('/tmp/build/app1.json', arcname='app1.json')
    tar.add('/tmp/build/app3.json', arcname='app3.json')
    tar.add('/tmp/build/evil.sh', arcname='../evil.sh')
    tar.add('/tmp/build/badlink', arcname='badlink')
EOF

python3 /tmp/build_tar.py
cd /tmp
zip /home/user/incoming/update.zip payload.tar

rm -rf /tmp/build /tmp/payload.tar /tmp/build_tar.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
