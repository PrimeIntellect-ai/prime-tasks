#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak
pip3 install pytest

mkdir -p /app/corpora/clean /app/corpora/evil

espeak -w /app/sysadmin_memo.wav "We use a custom write-ahead log for our system state. Block any archive that contains a file with the dot wal extension. I repeat, drop any archive containing a dot wal file."

cat << 'EOF' > /tmp/make_tars.py
import tarfile

def make_tar(path, files):
    with tarfile.open(path, 'w') as tar:
        for name in files:
            ti = tarfile.TarInfo(name)
            ti.size = 0
            tar.addfile(ti)

make_tar('/app/corpora/clean/clean1.tar', ['config/settings.json'])
make_tar('/app/corpora/clean/clean2.tar', ['app/data/info.txt'])
make_tar('/app/corpora/clean/clean3.tar', ['walrus.txt'])

make_tar('/app/corpora/evil/evil1.tar', ['../etc/passwd'])
make_tar('/app/corpora/evil/evil2.tar', ['/root/secret.txt'])
make_tar('/app/corpora/evil/evil3.tar', ['config/database.wal'])
make_tar('/app/corpora/evil/evil4.tar', ['nested/dir/../../../escape.sh'])
EOF

python3 /tmp/make_tars.py
rm /tmp/make_tars.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
