#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        wget \
        build-essential \
        zlib1g-dev \
        autoconf \
        automake \
        libtool

    pip3 install pytest

    # Setup libtar vendored package
    wget https://github.com/tklauser/libtar/archive/refs/tags/v1.2.20.tar.gz
    tar xzf v1.2.20.tar.gz
    mkdir -p /app
    mv libtar-1.2.20 /app/
    cd /app/libtar-1.2.20
    autoreconf -ivf
    cd /

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create configuration file
    cat <<EOF > /home/user/filter.conf
ALLOWED_PREFIX=dataset_
MAX_FILES=100
EOF

    # Create datasets using a python script
    cat <<'EOF' > /tmp/create_datasets.py
import tarfile
import os

os.makedirs('/app/datasets/clean', exist_ok=True)
os.makedirs('/app/datasets/evil', exist_ok=True)

# Clean
with tarfile.open('/app/datasets/clean/clean1.tar', 'w') as t:
    open('dataset_1.txt', 'w').close()
    open('dataset_2.txt', 'w').close()
    t.add('dataset_1.txt')
    t.add('dataset_2.txt')

# Evil 1: ../dataset_escape.txt
with tarfile.open('/app/datasets/evil/evil1.tar', 'w') as t:
    ti = tarfile.TarInfo('../dataset_escape.txt')
    ti.size = 0
    t.addfile(ti)

# Evil 2: /etc/dataset_passwd
with tarfile.open('/app/datasets/evil/evil2.tar', 'w') as t:
    ti = tarfile.TarInfo('/etc/dataset_passwd')
    ti.size = 0
    t.addfile(ti)

# Evil 3: truncated
with tarfile.open('/app/datasets/evil/evil3_temp.tar', 'w') as t:
    with open('dataset_valid.txt', 'w') as f:
        f.write('a'*10000)
    t.add('dataset_valid.txt')
with open('/app/datasets/evil/evil3_temp.tar', 'rb') as f:
    data = f.read()
with open('/app/datasets/evil/evil3.tar', 'wb') as f:
    f.write(data[:len(data)//2])
os.remove('/app/datasets/evil/evil3_temp.tar')

# Evil 4: 105 files
with tarfile.open('/app/datasets/evil/evil4.tar', 'w') as t:
    for i in range(105):
        ti = tarfile.TarInfo(f'dataset_{i}.txt')
        ti.size = 0
        t.addfile(ti)

# Evil 5: wrongprefix_data.txt
with tarfile.open('/app/datasets/evil/evil5.tar', 'w') as t:
    ti = tarfile.TarInfo('wrongprefix_data.txt')
    ti.size = 0
    t.addfile(ti)
EOF

    python3 /tmp/create_datasets.py
    rm /tmp/create_datasets.py

    chmod -R 777 /home/user
