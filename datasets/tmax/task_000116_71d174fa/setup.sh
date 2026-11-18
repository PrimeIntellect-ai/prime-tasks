#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/configs

    python3 -c "
import os
import time

configs_dir = '/home/user/configs'
os.makedirs(configs_dir, exist_ok=True)

def write_file(filename, content, days_ago, extra_size=0):
    path = os.path.join(configs_dir, filename)
    with open(path, 'wb') as f:
        f.write(content.encode('iso-8859-1'))
        if extra_size > 0:
            f.write(os.urandom(extra_size))

    mtime = time.time() - (days_ago * 24 * 3600)
    os.utime(path, (mtime, mtime))

write_file('app1.conf', '[general]\\nname=Système de test\\nserver_url=https://api.test.local/v1\\n', 2)
write_file('app2.conf', '[general]\\nname=Vieux système\\nserver_url=https://api.old.local/v1\\n', 10)
write_file('app3.conf', '[general]\\nname=Déploiement avancé\\nserver_url=https://api.prod.local/v2\\n', 1)
write_file('app4.conf', '[general]\\nname=Gros fichier\\nserver_url=https://api.big.local/v1\\n', 1, 12000)
"

    chmod -R 777 /home/user
