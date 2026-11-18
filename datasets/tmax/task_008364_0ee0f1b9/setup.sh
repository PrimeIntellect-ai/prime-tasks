#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils tar file coreutils
pip3 install pytest

mkdir -p /home/user/incoming
mkdir -p /home/user/extracted

# Create source files for ELF binaries
cat << 'EOF' > /tmp/main1.c
#include <stdio.h>
int main() { printf("Safe Binary 1\n"); return 0; }
EOF

cat << 'EOF' > /tmp/main2.c
#include <stdio.h>
int main() { printf("Safe Binary 2\n"); return 0; }
EOF

cat << 'EOF' > /tmp/main3.c
#include <stdio.h>
int main() { printf("Bad Binary\n"); return 0; }
EOF

# Compile them
gcc /tmp/main1.c -o /tmp/safe_bin_alpha
gcc /tmp/main2.c -o /tmp/safe_bin_beta
gcc /tmp/main3.c -o /tmp/bad_bin

echo "Just a text file" > /tmp/readme.txt

# Create Safe Archive 1
cd /tmp
tar -czf /home/user/incoming/build_1.tar.gz safe_bin_alpha readme.txt

# Create Safe Archive 2
mkdir -p /tmp/nested
cp /tmp/safe_bin_beta /tmp/nested/
cd /tmp
tar -czf /home/user/incoming/build_2.tar.gz nested/safe_bin_beta

# Create Malicious Archive 1 (Absolute Path)
cd /tmp
tar -czPcf /home/user/incoming/malicious_absolute.tar.gz /tmp/bad_bin

# Create Malicious Archive 2 (Relative Path traversal)
python3 -c "
import tarfile
import os

with tarfile.open('/home/user/incoming/malicious_relative.tar.gz', 'w:gz') as tar:
    info = tarfile.TarInfo(name='../sneaky_overwrite.txt')
    info.size = 12
    with open('/tmp/sneaky.txt', 'wb') as f:
        f.write(b'hacked file!')
    with open('/tmp/sneaky.txt', 'rb') as f:
        tar.addfile(info, f)
"

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/incoming /home/user/extracted
chmod -R 777 /home/user
