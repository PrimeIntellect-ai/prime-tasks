#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak zip
pip3 install pytest

mkdir -p /app/corpus/clean
mkdir -p /app/corpus/evil/evil_1
mkdir -p /app/corpus/evil/evil_2
mkdir -p /app/corpus/evil/evil_3
mkdir -p /app/corpus/evil/evil_4
mkdir -p /app/corpus/evil/evil_5
mkdir -p /home/user/raw_docs

# Generate audio
espeak -w /app/interview.wav "Create a directory called release_v2. Hard link the intro dot json file to index dot json. Create a symlink from attachments slash firmware dot elf to bin slash main dot elf."

# raw_docs
echo '{"intro": "Welcome"}' > /home/user/raw_docs/intro.json

# Clean corpus
echo '{"valid": "json"}' > /app/corpus/clean/file.json
echo '<valid>xml</valid>' > /app/corpus/clean/file.xml

# Evil 1: zip with symlink to ../../etc/passwd
cd /app/corpus/evil/evil_1
ln -s ../../etc/passwd passwd_link
zip --symlinks evil.zip passwd_link
rm passwd_link
cd -

# Evil 2: malformed JSON
echo '{"invalid": json' > /app/corpus/evil/evil_2/bad.json

# Evil 3: recursive symlink loop
ln -s loop /app/corpus/evil/evil_3/loop

# Evil 4: zip bomb (highly compressed XML)
dd if=/dev/zero bs=1M count=50 | tr '\0' 'a' > /tmp/big.xml
echo '<root>' > /app/corpus/evil/evil_4/bomb.xml
cat /tmp/big.xml >> /app/corpus/evil/evil_4/bomb.xml
echo '</root>' >> /app/corpus/evil/evil_4/bomb.xml
zip -j /app/corpus/evil/evil_4/bomb.zip /app/corpus/evil/evil_4/bomb.xml
rm /tmp/big.xml /app/corpus/evil/evil_4/bomb.xml

# Evil 5: ELF with corrupted header
echo -n -e '\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00' > /app/corpus/evil/evil_5/bad.elf
echo "corrupted" >> /app/corpus/evil/evil_5/bad.elf

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
