#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip wget zip unzip curl
pip3 install pytest

mkdir -p /app/corpora/evil /app/corpora/clean /app/patool-1.12

# Vendor Patool
cd /app
wget https://files.pythonhosted.org/packages/source/p/patool/patool-1.12.tar.gz
tar -xzf patool-1.12.tar.gz
rm patool-1.12.tar.gz

# Apply perturbation
python3 -c "
import os
path = '/app/patool-1.12/patoolib/util.py'
with open(path, 'r') as f:
    content = f.read()
if 'def check_existing_filename(filename):' in content:
    content = content.replace('def check_existing_filename(filename):', 'def check_existing_filename(filename) ->')
else:
    content += '\ndef check_existing_filename(filename) ->\n'
with open(path, 'w') as f:
    f.write(content)
"

# Generate clean corpus
cd /app/corpora/clean
mkdir -p clean_src
echo "Hello World" > clean_src/file1.txt
echo "Secret Data" > clean_src/file2.txt
cd clean_src && zip ../clean1.zip file1.txt file2.txt
cd .. && rm -rf clean_src

# Generate evil corpus
python3 -c "
import zipfile
with zipfile.ZipFile('/app/corpora/evil/evil1.zip', 'w') as z:
    z.writestr('../../../etc/shadow', 'fake shadow data')
with zipfile.ZipFile('/app/corpora/evil/evil2.zip', 'w') as z:
    z.writestr('/var/tmp/hacked.txt', 'fake hack')
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
